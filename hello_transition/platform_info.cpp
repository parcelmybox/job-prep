#include "platform_info.h"

std::string describe_target_platform() {
#if defined(__APPLE__) && defined(__aarch64__)
    return "Hello World from macOS Apple Silicon (arm64 / Mach-O)!";
#elif defined(__APPLE__) && defined(__x86_64__)
    return "Hello World from macOS Intel (x86_64 / Mach-O)!";
#elif defined(__linux__) && defined(__x86_64__)
    return "Hello World from Linux x86_64 (ELF)!";
#elif defined(__linux__) && defined(__aarch64__)
    return "Hello World from Linux ARM64 / aarch64 (ELF)!";
#else
    return "Hello World from unknown architecture!";
#endif
}
