
#ifndef HWY_COMPILE_ALL_ATTAINABLE
#define HWY_COMPILE_ALL_ATTAINABLE
#endif 

#if defined(_M_IX86) || defined(_M_X64)

//MSVC AVX3 was apparently fixed in a later version
    #if _MSC_VER >= 1929
        #define HWY_BROKEN_MSVC 0
        #define HWY_BROKEN_32BIT 0
    #endif

    #define HWY_WANT_SSE2 1 
    #define HWY_WANT_SSE3 1
    #define HWY_WANT_SSE4 1
    #define HWY_WANT_SSSE3 1


#endif

//Disable scalar and emulation - we have our own default implementaions for when SIMD is not allowed/enabled
//SSE2 seems to have issues - so don't generate support for SSE2
#ifndef HWY_DISABLED_TARGETS
#define HWY_DISABLED_TARGETS (HWY_EMU128 | HWY_SCALAR )
#endif


#ifdef HWY_TARGET_INCLUDE
#include <hwy/foreach_target.h>  // IWYU pragma: keep
#endif 

#include <hwy/highway.h>
#include <hwy/aligned_allocator.h>
#include <hwy/cache_control.h>
#include <hwy/print-inl.h>
