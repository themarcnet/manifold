
#if HWY_ONCE || HWY_IDE
namespace hwy
{
    enum RunHighwayErrorCode
    {
        RunHighwayErrorCode_Success = 0,
        RunHighwayErrorCode_Target_Out_Of_Range = 1,
        RunHighwayErrorCode_Target_Not_Implemented = 2,
        RunHighwayErrorCode_Target_Not_Supported = 3,
        RunHighwayErrorCode_Disabled = 4,
        RunHighwayErrorCode_Error = 5
    };


    //Wrapper around the highway dispatch mechanism that also allows the 
    //chosen implementation to be overridden(target > 0)
    template<typename T, typename FUNCTBL, typename... P>
    static inline RunHighwayErrorCode RunHighwayFunction(int target, T ** ret, FUNCTBL & table, P... params)
    {
        //Use automatic runtime CPU detection if target is zero
        if(target == 0)
        {
            const hwy::ChosenTarget & chosen = hwy::GetChosenTarget();
            *ret =  table[chosen.GetIndex()](params...);
            return (*ret == NULL) ? RunHighwayErrorCode_Error :  RunHighwayErrorCode_Success;
        }

        //Make sure target is in range
        if(target >= (sizeof(table) / sizeof(table[0])))
        {   
            *ret = NULL;
            return RunHighwayErrorCode_Target_Out_Of_Range;
        }

        //Don't allow unsupported targets (avoid illegal instruction errors)
        const int64_t supported = hwy::SupportedTargets();
        if(((1LL << target) & supported) == 0)
        {   
            *ret =  NULL;
            
            if(((1LL << target) & HWY_DISABLED_TARGETS) != 0)
                return RunHighwayErrorCode_Disabled; 

            return RunHighwayErrorCode_Target_Not_Supported;
        }

         //Make sure function pointer is not NULL
        if(table[target+1] == NULL)
        {
            *ret = NULL;
            return RunHighwayErrorCode_Target_Not_Implemented;
        }

        //Use specified CPU implementation
        *ret = table[target+1](params...);
        return (*ret == NULL) ? RunHighwayErrorCode_Error :  RunHighwayErrorCode_Success;
    }
}
#endif

#include <hwy/print-inl.h>
#include <hwy/print.h>


HWY_BEFORE_NAMESPACE();
namespace hwy
{
    namespace HWY_NAMESPACE
    {
        struct Utils
        {
            template<class V, class I, class X, 
                     int VN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<V>),
                     int IN  = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<I>),
                     int XN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<X>) >
                static HWY_INLINE void TableLookupLanes(const V & vec, const I & indvec, X & out,
                                                        typename std::enable_if< ((VN == (IN / 2)) && (XN == IN)), void>::type * = nullptr)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const hwy::HWY_NAMESPACE::DFromV<I> _indtype;
                const hwy::HWY_NAMESPACE::DFromV<X> _outtype;
                const hwy::HWY_NAMESPACE::Half<hwy::HWY_NAMESPACE::DFromV<I>> _halfindtype;
                const hwy::HWY_NAMESPACE::Half<hwy::HWY_NAMESPACE::DFromV<X>> _halfouttype;
                
                auto indiciesupper = HWY::IndicesFromVec(_halfindtype, HWY::UpperHalf(_halfindtype, indvec));
                auto indicieslower = HWY::IndicesFromVec(_halfindtype, HWY::LowerHalf(_halfindtype, indvec));

                auto outlower = HWY::TableLookupLanes(HWY::BitCast(_halfindtype,vec), indicieslower);
                auto outupper = HWY::TableLookupLanes(HWY::BitCast(_halfindtype,vec), indiciesupper);

                out = HWY::Combine(_outtype, HWY::BitCast(_halfouttype,  outupper), HWY::BitCast(_halfouttype, outlower));
            }

            template<class V, class I, class X, 
                     int VN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<V>),
                     int IN  = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<I>),
                     int XN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<X>) >
                static HWY_INLINE void TableLookupLanes(const V & vec, const I & indvec, X & out,
                                                        typename std::enable_if< ((VN == (IN / 2)) && (XN == (IN/2))), void>::type * = nullptr)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const hwy::HWY_NAMESPACE::DFromV<V> _vectype;
                const hwy::HWY_NAMESPACE::DFromV<I> _indtype;
                const hwy::HWY_NAMESPACE::DFromV<X> _outtype;

                auto indicies = HWY::IndicesFromVec(_indtype, indvec);
                out = HWY::TableLookupLanes(vec, indicies);
            }


            template<class V, class I, class X, 
                     int VN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<V>),
                     int IN  = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<I>),
                     int XN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<X>) >
                static HWY_INLINE void TableLookupLanes(const V & vec, const I & indvec, X & out,
                                                        typename std::enable_if< ((VN==IN) && (XN == IN)), void>::type * = nullptr)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const hwy::HWY_NAMESPACE::DFromV<I> _indtype;
                const hwy::HWY_NAMESPACE::DFromV<X> _outtype;
                
                auto indicies = HWY::IndicesFromVec(_indtype, indvec);
                out = HWY::BitCast(_outtype, HWY::TableLookupLanes( HWY::BitCast(_indtype,vec), indicies));
            }
            /*
            template<class V, class I, class X, 
                     int VN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<V>),
                     int IN  = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<I>),
                     int XN = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<X>) >
                static HWY_INLINE void TableLookupLanes(const V & vec, const I & indvec, X & out,
                                                        typename std::enable_if< (((VN/2) == IN) && (XN == IN)), void>::type * = nullptr)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const hwy::HWY_NAMESPACE::DFromV<V> _vectype;
                const hwy::HWY_NAMESPACE::DFromV<I> _indtype;
                const hwy::HWY_NAMESPACE::DFromV<X> _outtype;

                auto indicies = HWY::IndicesFromVec(_indtype, indvec);
                auto upper = HWY::UpperHalf(_vectype, vec);
                auto lower = HWY::LowerHalf(_vectype, vec);
                out = HWY::TwoTablesLookupLanes(vec, lower, upper, indicies);
            }*/
        };

        struct Debug
        {
            template<class L, typename H>
            static HWY_INLINE void OutputLanes( L & log, size_t x, const char * caption, const H & val)
            {
                const hwy::HWY_NAMESPACE::DFromV<H> _type;
                
                HWY_ALIGN hwy::HWY_NAMESPACE::TFromV<H> lanes[_type.MaxLanes()];

                hwy::HWY_NAMESPACE::Store(val, _type, lanes);

                for(size_t i = 0; i < _type.MaxLanes(); ++i)
                {
                    log.LogValue(x + i, caption, lanes[i]);
                }
            }

            template<class L, typename H, typename M>
            static HWY_INLINE void OutputLanesMask( L & log, size_t x, const char * caption, const H & val, const M & mask)
            {
                const hwy::HWY_NAMESPACE::DFromV<H> _type;
                const hwy::HWY_NAMESPACE::DFromV<M> _masktype;
                
                HWY_ALIGN hwy::HWY_NAMESPACE::TFromV<H> lanes[_type.MaxLanes()];

                hwy::HWY_NAMESPACE::Store(val, _type, lanes);
                const uint64_t m = hwy::HWY_NAMESPACE::BitsFromMask(_masktype, mask);
                for(size_t i = 0; i < _type.MaxLanes(); ++i)
                {
                    if((m >> i) & 1)
                        log.LogValue(x + i, caption, lanes[i]);
                }
            }
        };
    }
}
HWY_AFTER_NAMESPACE();


