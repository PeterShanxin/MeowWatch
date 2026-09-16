#ifndef RUNNER_LAN_INTERFACES_H_
#define RUNNER_LAN_INTERFACES_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

class LanInterfacesChannel {
 public:
  explicit LanInterfacesChannel(flutter::BinaryMessenger* messenger);
  ~LanInterfacesChannel();

 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_LAN_INTERFACES_H_
