#include "lan_interfaces.h"

#include <winsock2.h>
#include <ws2tcpip.h>

#include <flutter/standard_method_codec.h>
#include <iphlpapi.h>
#include <netlistmgr.h>
#include <wrl/client.h>

#include <cstdint>
#include <iterator>
#include <string>
#include <utility>
#include <vector>

#include "utils.h"

namespace {

using Microsoft::WRL::ComPtr;

enum class NetworkProfile {
  kPrivate,
  kPublic,
  kDomainAuthenticated,
  kUnknown,
};

struct AdapterProfile {
  GUID adapter_id;
  NetworkProfile profile;
};

struct AdapterQueryResult {
  DWORD error = NO_ERROR;
  flutter::EncodableList adapters;
};

NetworkProfile MergeProfiles(NetworkProfile current,
                             NetworkProfile incoming) {
  if (current == NetworkProfile::kPublic ||
      incoming == NetworkProfile::kPublic) {
    return NetworkProfile::kPublic;
  }
  if (current == NetworkProfile::kUnknown ||
      incoming == NetworkProfile::kUnknown) {
    return NetworkProfile::kUnknown;
  }
  if (current == NetworkProfile::kDomainAuthenticated ||
      incoming == NetworkProfile::kDomainAuthenticated) {
    return NetworkProfile::kDomainAuthenticated;
  }
  return NetworkProfile::kPrivate;
}

std::vector<AdapterProfile> ReadConnectedNetworkProfiles() {
  ComPtr<INetworkListManager> manager;
  if (FAILED(::CoCreateInstance(__uuidof(NetworkListManager), nullptr,
                                CLSCTX_ALL, IID_PPV_ARGS(&manager)))) {
    return {};
  }

  ComPtr<IEnumNetworkConnections> connections;
  if (FAILED(manager->GetNetworkConnections(&connections))) {
    return {};
  }

  std::vector<AdapterProfile> profiles;
  while (true) {
    ComPtr<INetworkConnection> connection;
    ULONG fetched = 0;
    const HRESULT next =
        connections->Next(1, connection.ReleaseAndGetAddressOf(), &fetched);
    if (next != S_OK || fetched != 1) {
      break;
    }

    VARIANT_BOOL connected = VARIANT_FALSE;
    GUID adapter_id{};
    if (FAILED(connection->GetAdapterId(&adapter_id))) {
      continue;
    }

    const HRESULT connected_result = connection->get_IsConnected(&connected);
    if (SUCCEEDED(connected_result) && connected != VARIANT_TRUE) {
      continue;
    }

    ComPtr<INetwork> network;
    NLM_NETWORK_CATEGORY category = NLM_NETWORK_CATEGORY_PUBLIC;
    const NetworkProfile profile = [&]() {
      if (FAILED(connected_result)) {
        return NetworkProfile::kUnknown;
      }
      if (FAILED(connection->GetNetwork(&network)) ||
          FAILED(network->GetCategory(&category))) {
        return NetworkProfile::kUnknown;
      }
      switch (category) {
        case NLM_NETWORK_CATEGORY_PRIVATE:
          return NetworkProfile::kPrivate;
        case NLM_NETWORK_CATEGORY_DOMAIN_AUTHENTICATED:
          return NetworkProfile::kDomainAuthenticated;
        case NLM_NETWORK_CATEGORY_PUBLIC:
          return NetworkProfile::kPublic;
        default:
          return NetworkProfile::kUnknown;
      }
    }();

    bool merged = false;
    for (auto& existing : profiles) {
      if (::InlineIsEqualGUID(existing.adapter_id, adapter_id)) {
        existing.profile = MergeProfiles(existing.profile, profile);
        merged = true;
        break;
      }
    }
    if (!merged) {
      profiles.push_back({adapter_id, profile});
    }
  }
  return profiles;
}

std::string ProfileName(const GUID& interface_guid,
                        const std::vector<AdapterProfile>& profiles) {
  for (const auto& entry : profiles) {
    if (::InlineIsEqualGUID(entry.adapter_id, interface_guid)) {
      switch (entry.profile) {
        case NetworkProfile::kPrivate:
          return "private";
        case NetworkProfile::kPublic:
          return "public";
        case NetworkProfile::kDomainAuthenticated:
          return "domainAuthenticated";
        case NetworkProfile::kUnknown:
          return "unknown";
      }
    }
  }
  // Missing or failed NLM classification stays unknown. Dart treats unknown as
  // ineligible for automatic Nearby enablement.
  return "unknown";
}

std::string GuidString(const GUID& guid) {
  wchar_t value[39] = {};
  if (::StringFromGUID2(guid, value, static_cast<int>(std::size(value))) == 0) {
    return {};
  }
  return Utf8FromUtf16(value);
}

bool IsSupportedLanAddress(const IN_ADDR& address) {
  const uint32_t value = ntohl(address.S_un.S_addr);
  const uint8_t first = static_cast<uint8_t>(value >> 24);
  const uint8_t second = static_cast<uint8_t>((value >> 16) & 0xff);
  return first == 10 ||
         (first == 172 && second >= 16 && second <= 31) ||
         (first == 192 && second == 168) ||
         (first == 169 && second == 254);
}

bool IsUsableSourceAddress(const IP_ADAPTER_ADDRESSES& adapter,
                           const sockaddr_in& address) {
  MIB_UNICASTIPADDRESS_ROW row{};
  ::InitializeUnicastIpAddressEntry(&row);
  row.Address.Ipv4 = address;
  row.InterfaceLuid = adapter.Luid;
  return ::GetUnicastIpAddressEntry(&row) == NO_ERROR &&
         row.DadState == IpDadStatePreferred && !row.SkipAsSource;
}

bool ReadPhysicalInterface(const IP_ADAPTER_ADDRESSES& adapter,
                           MIB_IF_ROW2* row) {
  if (adapter.OperStatus != IfOperStatusUp ||
      adapter.ConnectionType != NET_IF_CONNECTION_DEDICATED ||
      (adapter.IfType != IF_TYPE_ETHERNET_CSMACD &&
       adapter.IfType != IF_TYPE_IEEE80211)) {
    return false;
  }

  *row = {};
  row->InterfaceLuid = adapter.Luid;
  if (::GetIfEntry2(row) != NO_ERROR) {
    return false;
  }

  const auto& flags = row->InterfaceAndOperStatusFlags;
  return row->OperStatus == IfOperStatusUp &&
         row->ConnectionType == NET_IF_CONNECTION_DEDICATED &&
         flags.HardwareInterface && flags.ConnectorPresent &&
         !flags.FilterInterface && !flags.NotMediaConnected &&
         !flags.EndPointInterface;
}

AdapterQueryResult QueryAdapters() {
  constexpr ULONG kFlags =
      GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
      GAA_FLAG_SKIP_DNS_SERVER | GAA_FLAG_INCLUDE_PREFIX;
  ULONG buffer_size = 15 * 1024;
  std::vector<unsigned char> buffer(buffer_size);
  DWORD result = ERROR_BUFFER_OVERFLOW;

  for (int attempt = 0; attempt < 3 && result == ERROR_BUFFER_OVERFLOW;
       ++attempt) {
    result = ::GetAdaptersAddresses(
        AF_INET, kFlags, nullptr,
        reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()), &buffer_size);
    if (result == ERROR_BUFFER_OVERFLOW) {
      buffer.resize(buffer_size);
    }
  }
  if (result != NO_ERROR) {
    AdapterQueryResult failed;
    failed.error = result;
    return failed;
  }

  const auto profiles = ReadConnectedNetworkProfiles();
  flutter::EncodableList output;
  auto* adapter = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  for (; adapter != nullptr; adapter = adapter->Next) {
    MIB_IF_ROW2 interface_row{};
    if (!ReadPhysicalInterface(*adapter, &interface_row)) {
      continue;
    }

    const std::string interface_id = GuidString(interface_row.InterfaceGuid);
    std::string friendly_name = Utf8FromUtf16(adapter->FriendlyName);
    if (interface_id.empty()) {
      continue;
    }
    if (friendly_name.empty()) {
      friendly_name = interface_id;
    }

    for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr;
         unicast = unicast->Next) {
      if (unicast->Address.lpSockaddr == nullptr ||
          unicast->Address.iSockaddrLength <
              static_cast<int>(sizeof(sockaddr_in)) ||
          unicast->Address.lpSockaddr->sa_family != AF_INET ||
          unicast->DadState != IpDadStatePreferred ||
          unicast->OnLinkPrefixLength < 1 ||
          unicast->OnLinkPrefixLength > 32) {
        continue;
      }

      const auto* socket_address = reinterpret_cast<const sockaddr_in*>(
          unicast->Address.lpSockaddr);
      if (!IsSupportedLanAddress(socket_address->sin_addr) ||
          !IsUsableSourceAddress(*adapter, *socket_address)) {
        continue;
      }

      char address[INET_ADDRSTRLEN] = {};
      if (::InetNtopA(AF_INET, &socket_address->sin_addr, address,
                      static_cast<DWORD>(std::size(address))) == nullptr) {
        continue;
      }

      output.push_back(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("address"),
           flutter::EncodableValue(std::string(address))},
          {flutter::EncodableValue("prefixLength"),
           flutter::EncodableValue(
               static_cast<int32_t>(unicast->OnLinkPrefixLength))},
          {flutter::EncodableValue("interfaceIndex"),
           flutter::EncodableValue(static_cast<int64_t>(adapter->IfIndex))},
          {flutter::EncodableValue("interfaceId"),
           flutter::EncodableValue(interface_id)},
          {flutter::EncodableValue("friendlyName"),
           flutter::EncodableValue(friendly_name)},
          {flutter::EncodableValue("profile"),
           flutter::EncodableValue(
               ProfileName(interface_row.InterfaceGuid, profiles))},
      }));
    }
  }

  AdapterQueryResult succeeded;
  succeeded.adapters = std::move(output);
  return succeeded;
}

}  // namespace

LanInterfacesChannel::LanInterfacesChannel(
    flutter::BinaryMessenger* messenger) {
  channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "meowwatch/lan_interfaces",
          &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "listIPv4") {
          result->NotImplemented();
          return;
        }

        auto query = QueryAdapters();
        if (query.error != NO_ERROR) {
          result->Error(
              "lan_interfaces_error", "Windows could not list LAN adapters",
              flutter::EncodableValue(static_cast<int64_t>(query.error)));
          return;
        }
        result->Success(flutter::EncodableValue(std::move(query.adapters)));
      });
}

LanInterfacesChannel::~LanInterfacesChannel() = default;
