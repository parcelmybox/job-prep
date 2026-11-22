#include <iostream>
#include "platform_info.h"

int main() {
    std::cout << describe_target_platform() << std::endl;
    return 0;
}
