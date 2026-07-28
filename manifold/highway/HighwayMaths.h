//Redefine the Highway Math implementation methods, so we can override them
//We bascially use Intel SVML to implement them, if SVML is available, and
//revert to the original implementation (as redefined below) if SVML is not available.
#define SinCos __SinCos
#define Exp __Exp
#define Atan __Atan
#define Tanh __Tanh


#include "hwy/contrib/math/math-inl.h"

//Remove our redefinitions
#undef SinCos
#undef Exp
#undef Atan
#undef Tanh

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
        template<typename T, class D, int64_t X, typename ENABLE = void>
        struct HwyMathImpl
        {
            template <class DN, class V>
            static HWY_INLINE V Atan(const DN d, V val)
            {
                //Call the original version that we # redefined
                return __Atan(d, val);
            }

            template <class DN, class V>
            static HWY_INLINE V Exp(const DN d, V val)
            {
                //Call the original version that we # redefined
                return __Exp(d, val);
            }

            template <class DN, class V>
            static HWY_INLINE void SinCos(const DN d, V x, V& s, V& c)
            {
                //Call the original version that we # redefined
                __SinCos(d, x, s, c);
            }

            template <class DN, class V>
            static HWY_INLINE V Tanh(const DN d, V val)
            {
                //Call the original version that we # redefined
                return __Tanh(d, val);
            }

            template <class DN, class V>
            static HWY_INLINE V Pow(const DN /*d*/, V val, V powval)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const hwy::HWY_NAMESPACE::ScalableTag< hwy::HWY_NAMESPACE::TFromV<V> > _vtype;
               
                const V minval = HWY::Set(_vtype, -126.99999f);
                const V maxval = HWY::Set(_vtype, 127.0f);

                //log2(x) * y
                V log2y = HWY::Log2(_vtype, val);
                log2y = HWY::Mul(log2y, powval);

                //Calculate exp2(log2(x) * y)
                log2y = HWY::IfThenElse(HWY::Lt(log2y, minval), minval, log2y);
                log2y = HWY::IfThenElse(HWY::Gt(log2y, maxval), maxval, log2y);
                V exp2LogY = HWY::Exp2(_vtype, log2y);

                return exp2LogY;
            }
        };

        //AVX512
        template<class D, int64_t X>
        struct HwyMathImpl<float, D, X,
                           hwy::EnableIf<HWY_FLAG_CHECK_AVX3(X) && (HWY_MAX_LANES_D(D) * sizeof(float) == 64)>>
        {
            template <class DN, class V>
            static HWY_INLINE V Atan(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm512_atan_ps(val.raw);
                return ret;
            }

            template <class DN, class V>
            static HWY_INLINE V Exp(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm512_exp_ps(val.raw);
                return ret;
            }

            template <class DN, class V>
            static HWY_INLINE void SinCos(const DN d, V x, V& s, V& c)
            {
                s.raw = _mm512_sincos_ps(&c.raw, x.raw);
            }

            template <class DN, class V>
            static HWY_INLINE V Tanh(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm512_tanh_ps(val.raw);
                return ret;
            }


            template <class DN, class V>
            static HWY_INLINE V Pow(const DN d, V a, V b)
            {
                V ret;
                ret.raw = _mm512_pow_ps(a.raw, b.raw);
                return ret;
            }
        };

        //AVX2
        template<class D, int64_t X>
        struct HwyMathImpl<float, D, X,
                           hwy::EnableIf<HWY_FLAG_CHECK_AVX_AVX3(X) && (HWY_MAX_LANES_D(D) * sizeof(float) == 32)>>
        {
            template <class DN, class V>
            static HWY_INLINE V Atan(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm256_atan_ps(val.raw);
                return ret;
            }

            template <class DN, class V>
            static HWY_INLINE V Exp(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm256_exp_ps(val.raw);
                return ret;
            }

            template <class DN, class V>
            static HWY_INLINE void SinCos(const DN d, V x, V& s, V& c)
            {
                s.raw = _mm256_sincos_ps(&c.raw, x.raw);
            }

            template <class DN, class V>
            static HWY_INLINE V Tanh(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm256_tanh_ps(val.raw);
                return ret;
            }


            template <class DN, class V>
            static HWY_INLINE V Pow(const DN d, V a, V b)
            {
                V ret;
                ret.raw = _mm256_pow_ps(a.raw, b.raw);
                return ret;
            }
        };
        
        //SSE
        template<class D, int64_t X>
        struct HwyMathImpl<float, D, X,
                          hwy::EnableIf<HWY_FLAG_CHECK_SSE_AVX_AVX3(X) && (HWY_MAX_LANES_D(D) * sizeof(float) == 16)>>
        {
            template <class DN, class V>
            static HWY_INLINE V Atan(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm_atan_ps(val.raw);
                return ret;
            }

            template <class DN, class V>
            static HWY_INLINE V Exp(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm_exp_ps(val.raw);
                return ret;
            }

            template <class DN, class V>
            static HWY_INLINE void SinCos(const DN d, V x, V& s, V& c)
            {
                s.raw = _mm_sincos_ps(&c.raw, x.raw);
            }

            template <class DN, class V>
            static HWY_INLINE V Tanh(const DN /*d*/, V val)
            {
                V ret;
                ret.raw = _mm_tanh_ps(val.raw);
                return ret;
            }

            template <class DN, class V>
            static HWY_INLINE V Pow(const DN d, V a, V b)
            {
                //This is not as accurate as the 256-bit version, but we can't 
                //use that here since we're SSE only
                /*V ret;
                ret.raw = _mm_pow_ps(a.raw, b.raw);

                
                return ret;*/

                //So revert to the default implementation
                return hwy::HWY_NAMESPACE::HwyMathImpl<float, D, 0>::Pow(d, a, b);
            }
        };

        //================================================================

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Atan(const D d, V a)
        {
            using T = TFromD<D>;
            return HwyMathImpl<T, D, X>::Atan(d, a);
        }

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Exp(const D d, V val)
        {
            using T = TFromD<D>;
            auto ret = HwyMathImpl<T, D, X>::Exp(d, val);
            return ret;
        }

        template < class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Fmod( V a, V b)
        {
            namespace HWY = hwy::HWY_NAMESPACE;
            return HWY::NegMulAdd(HWY::Trunc(HWY::Div(a, b)), b, a);
        }

        template < class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Limit( V minval, V maxval, V val)
        {
            namespace HWY = hwy::HWY_NAMESPACE;
            return HWY::IfThenElse(HWY::Gt(val, maxval), maxval, HWY::IfThenElse(HWY::Lt(val, minval), minval, val));
        }

        template <class M, class V, int64_t X = HWY_TARGET>
        HWY_INLINE V MaskedLimit(V no, M mask, V minval, V maxval, V val)
        {
            namespace HWY = hwy::HWY_NAMESPACE;
            return HWY::IfThenElse(mask, HWY::IfThenElse(HWY::Gt(val, maxval), maxval, HWY::IfThenElse(HWY::Lt(val, minval), minval, val)), no);
        }

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE void SinCos(const D d, V x, V& s, V& c)
        {
            using T = TFromD<D>;
            HwyMathImpl<T, D, X>::SinCos(d, x, s, c);
        }

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Sqrt(const D d, V val)
        {
            using T = TFromD<D>;
            auto ret = HwyMathImpl<T, D, X>::Sqrt(d, val);
            return ret;
        }

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Tanh(const D d, V val)
        {
            using T = TFromD<D>;
            auto ret = HwyMathImpl<T, D, X>::Tanh(d, val);
            return ret;
        }

        template <class D, class V, int64_t X = HWY_TARGET>
        HWY_INLINE V Pow(const D d, V a, V b)
        {
            using T = TFromD<D>;
            return HwyMathImpl<T, D, X>::Pow(d, a, b);
        }

        // NOLINTNEXTLINE(google-readability-namespace-comments)
    }  // namespace HWY_NAMESPACE
}  // namespace hwy
HWY_AFTER_NAMESPACE();
