// Stub for OpenMP functions referenced by prebuilt ncnn/opencv
// (compiled with older NDK that used __kmpc_* ABI).
// NDK 27+ use __kmp_* ABI. These stubs are no-ops — the
// only OpenMP pragma in our code (ppocrv5.cpp) is already disabled.
extern "C" {

void __kmpc_dispatch_deinit(int gtid) { (void)gtid; }

} // extern "C"
