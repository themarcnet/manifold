
#define SinCos __SinCos

#include "hwy/contrib/math/math-inl.h"

#undef SinCos


//==================================================================
//Discover if SVML is available
#ifndef HWY_ARCH_X86
#if defined(_M_IX86)
#  define HWY_ARCH_X86 (_M_IX86 / 100)
#elif defined(__I86__)
#  define HWY_ARCH_X86 __I86__
#elif defined(i686) || defined(__i686) || defined(__i686__)
#  define HWY_ARCH_X86 6
#elif defined(i586) || defined(__i586) || defined(__i586__)
#  define HWY_ARCH_X86 5
#elif defined(i486) || defined(__i486) || defined(__i486__)
#  define HWY_ARCH_X86 4
#elif defined(i386) || defined(__i386) || defined(__i386__)
#  define HWY_ARCH_X86 3
#elif defined(_X86_) || defined(__X86__) || defined(__THW_INTEL__)
#  define HWY_ARCH_X86 3
#endif
#endif 

#if defined(_MSC_VER) && (_MSC_VER >= 1400)
#  define HWYMATHS_MSVC_VERSION_CHECK(major,minor,patch) (_MSC_FULL_VER >= ((major * 10000000) + (minor * 100000) + (patch)))
#elif defined(_MSC_VER) && (_MSC_VER >= 1200)
#  define HWYMATHS_MSVC_VERSION_CHECK(major,minor,patch) (_MSC_FULL_VER >= ((major * 1000000) + (minor * 10000) + (patch)))
#else
#  define HWYMATHS_MSVC_VERSION_CHECK(major,minor,patch) (_MSC_VER >= ((major * 100) + (minor)))
#endif

#if defined(HWY_ARCH_X86) && (defined(__INTEL_COMPILER) || (HWYMATHS_MSVC_VERSION_CHECK(14, 20, 0) && !defined(__clang__)))
#define HWYX86_SVML_NATIVE ((1LL << HWY_HIGHEST_TARGET_BIT_SCALAR) - 1)
#else
#define HWYX86_SVML_NATIVE 0
#endif

//==================================================================
#define HWY_FLAG_CHECK_AVX3(X) (((X & HWYX86_SVML_NATIVE) & (HWY_AVX3 | HWY_AVX3_DL | HWY_AVX3_SPR | HWY_AVX3_ZEN4))  != 0)
#define HWY_FLAG_CHECK_AVX_AVX3(X)  (((X &HWYX86_SVML_NATIVE) & (HWY_AVX2 |  HWY_AVX3 | HWY_AVX3_DL | HWY_AVX3_SPR | HWY_AVX3_ZEN4))  != 0)
#define HWY_FLAG_CHECK_SSE_AVX_AVX3(X)  (((X & HWYX86_SVML_NATIVE) & (HWY_AVX2 | HWY_SSE2 | HWY_SSSE3 | HWY_SSE4 | HWY_AVX3 | HWY_AVX3_DL | HWY_AVX3_SPR | HWY_AVX3_ZEN4))  != 0)


HWY_BEFORE_NAMESPACE();
namespace hwy 
{
    namespace HWY_NAMESPACE 
    {
        //Default
        template< typename T, class D, int64_t X, typename ENABLE = void>
        struct HwyMathImpl
        {
            template <class D, class V>
            static HWY_INLINE void SinCos(const D d, V x, V& s, V& c)
            {
                //Call the original version that we # redefined
                __SinCos(d, x, s, c);
            }

            template <class D, class V>
            HWY_API V Pow(const D /*d*/, V val, V powval)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const hwy::HWY_NAMESPACE::ScalableTag<float> _flttype;
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::ScalableTag<float>> FltMaskType;

                const FltType minval = HWY::Set(_flttype, -126.99999f);
                const FltType maxval = HWY::Set(_flttype,129.0f);
                

                //log2(x) * y
                FltType log2y = HWY::Log2(_flttype, val);
                log2y = HWY::Mul(log2y,powval);

                //Calculate exp2(log2(x) * y)
                log2y = HWY::IfThenElse(HWY::Lt(log2y, minval), minval, log2y);
                log2y = HWY::IfThenElse(HWY::Gt(log2y, maxval),maxval, log2y);
                FltType exp2LogY = HWY::Exp2(_flttype, log2y);

              
                return exp2LogY;
            }
        };

        //AVX512
        template<class D, int64_t X>
        struct HwyMathImpl<float, D, X,
                           hwy::EnableIf< HWY_FLAG_CHECK_AVX3(X) && (HWY_MAX_LANES_D(D) * sizeof(float) == 64)> >
        {
            template <class D, class V>
            static HWY_INLINE void SinCos(const D d, V x, V& s, V& c)
            {
                s.raw = _mm512_sincos_ps(&c.raw, x.raw);
            }

            template <class D, class V>
            static HWY_INLINE V Pow(const D d, V a, V b)
            {
                V ret;
                ret.raw = _mm512_pow_ps(a.raw, b.raw);
                return ret;
            }
        };

        /*
        //AVX2
        template<class D, int64_t X>
        struct HwyMathImpl<float, D,X, 
                           hwy::EnableIf< HWY_FLAG_CHECK_AVX_AVX3(X) && (HWY_MAX_LANES_D(D) * sizeof(float) == 32)> >
        {
            template <class D, class V>
            static HWY_INLINE void SinCos(const D d, V x, V& s, V& c)
            {
                s.raw = _mm256_sincos_ps(&c.raw, x.raw);
            }

            template <class D, class V>
            static HWY_INLINE V Pow(const D d, V a, V b)
            {
                V ret;
                ret.raw = _mm256_pow_ps(a.raw, b.raw);
                return ret;
            }
        };
        */

        //SSE
        template<class D, int64_t X>
        struct HwyMathImpl<float, D,X, 
                          hwy::EnableIf< HWY_FLAG_CHECK_SSE_AVX_AVX3(X) && (HWY_MAX_LANES_D(D) * sizeof(float) == 16)> >
        {
            template <class D, class V>
            static HWY_INLINE void SinCos(const D d, V x, V& s, V& c)
            {
                s.raw = _mm_sincos_ps(&c.raw, x.raw);
            }

            template <class D, class V>
            static HWY_INLINE V Pow(const D d, V a, V b)
            {
                V ret;
                ret.raw = _mm_pow_ps(a.raw, b.raw);
                return ret;
            }
        };

        //================================================================

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE void SinCos(const D d, V x, V& s, V& c) 
        {
            using T = TFromD<D>;
            HwyMathImpl<T, D, X>::SinCos(d, x, s, c);
        }

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Pow(const D d, V a, V b) 
        {
            using T = TFromD<D>;
            return HwyMathImpl<T, D, X>::Pow(d, a,b);
        }

        // NOLINTNEXTLINE(google-readability-namespace-comments)
    }  // namespace HWY_NAMESPACE
}  // namespace hwy
HWY_AFTER_NAMESPACE();


