
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

        int curTarget = (HWY_HIGHEST_TARGET_BIT + 1 - HWY_MAX_DYNAMIC_TARGETS) + target;
        if(((1LL << curTarget) & supported) == 0)
        {   
            *ret =  NULL;
            
            if(((1LL << curTarget) & HWY_DISABLED_TARGETS) != 0)
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


HWY_BEFORE_NAMESPACE();
namespace hwy
{
    namespace HWY_NAMESPACE
    {
        struct Utils
        {
            template<class V>
            static HWY_ATTR HWY_INLINE  void BroadcastLastLane(const V & in, V & out)
            {
                const hwy::HWY_NAMESPACE::DFromV<V> _vectype;

                //On fixed width lanes, we can use constexpr Lanes() to get the last lane number
                //This is preferable on x86/x64, where reverse has as slight performance impace/
                //
                //On other platforms, such as ARM SVE, Reverse does not have such a performance impact, so
                //we can use Reverse and Broadcast lane 0 of the reversed vector
                //(Lanes() won't work here because it is not a const expression, and MaxLanes() is the wrong value)
                #if HWY_HAVE_CONSTEXPR_LANES
                    out = hwy::HWY_NAMESPACE::BroadcastLane<hwy::HWY_NAMESPACE::Lanes(_vectype) - 1>(in);
                #else
                    out = hwy::HWY_NAMESPACE::BroadcastLane<0>(hwy::HWY_NAMESPACE::Reverse(_vectype, in));
                #endif
            }

            template<class V>
            static HWY_ATTR HWY_INLINE  void BroadcastLastBlock(const V & in, V & out)
            {
                const hwy::HWY_NAMESPACE::DFromV<V> _vectype;
                
                //On fixed width lanes, we can use constexpr Blocks() to get the last block number
                //This is preferable on x86/x64, where reverse has as slight performance impace/
                //
                //On other platforms, such as ARM SVE, Reverse does not have such a performance impact, so
                //we can use ReverseBlocks and Broadcast Block 0 of the reversed vector -
                // Note that  ReverseBlocks reverses the order of the blocks, but keeps the values inside each block in the same order.
                //(Blocks() won't work here because it is not a const expression, and MaxBlocks() is the wrong value)
                //#if HWY_HAVE_CONSTEXPR_LANES
                //    out = hwy::HWY_NAMESPACE::BroadcastBlock<_vectype.MaxBlocks() - 1>(in);
                //#else
                    out = hwy::HWY_NAMESPACE::BroadcastBlock<0>(hwy::HWY_NAMESPACE::ReverseBlocks(_vectype,in));
                //#endif
            }

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
    }
}
HWY_AFTER_NAMESPACE();


