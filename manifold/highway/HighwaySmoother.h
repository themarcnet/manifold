#include <hwy/aligned_allocator.h>
#include <atomic>
#include <hwy/highway.h>

#include "manifold/highway/HighwayMultiVec.h"

/*
* This is a utility class for dealing with 'smoothing' of values via SIMD
* It can take N amount of values and perform the smoothing of them in one go.
* Each value is stored in a separate, meaning that one operation is needed to update them.
* The next part of taking the updates values and putting them into the correct value is a little more expensive...
*/

HWY_BEFORE_NAMESPACE();
namespace hwy
{
    namespace HWY_NAMESPACE
    {
        template<typename T, int COUNT, int ADD_FLAG = 0>
        class HighwayValueSmoother
        {
        private:

            //Round COUNT up to the next power of 2 - since CappedTag requires only powers of 2.
            static constexpr int _laneCount()
            {
                int v = COUNT - 1;
                v |= v >> 1;
                v |= v >> 2;
                v |= v >> 4;
                v |= v >> 8;
                v |= v >> 16;
                v++;
                return v;
            }

            struct _tmp
            {
                typedef hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::CappedTag<T, _laneCount()  >> VecType;
                typedef hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::CappedTag<T, _laneCount()  >> VecMaskType;
            };

            #if HWY_HAVE_CONSTEXPR_LANES
                struct _lc
                {
                    static constexpr size_t c_lane_count = HWY_LANES(_tmp::VecType);
                    static constexpr size_t c_want_lane_count = COUNT;
                    static constexpr size_t c_max_lane_count = _laneCount();
                };
            #else
                struct _lc
                {
                    //Types to use when the wanted lane count will fit inside a single vector
                    //Since we can't use Lanes() here, we'll assume the minimum 
                    static constexpr size_t c_lane_count = HWY_MIN_BYTES / 4;
                    static constexpr size_t c_want_lane_count = COUNT;
                    static constexpr size_t c_max_lane_count = _laneCount();
                };
            #endif

            template<int WC, int LC, typename ENABLE = void>
            struct SmootherTypes
            {};

            template<int WC,  int LC>
            struct SmootherTypes<WC,LC, hwy::EnableIf< ( WC <= LC ) >>
            {
                typedef typename _tmp::VecType VectorType;
                typedef typename _tmp::VecMaskType MaskType;
                typedef  hwy::HWY_NAMESPACE::DFromV<typename _tmp::VecType> _D;
            };

            template<int WC,  int LC>
            struct SmootherTypes<WC,LC,  hwy::EnableIf< ( WC > LC ) >>
            {
                //Use Multivec since there are too many lanes
                typedef typename hwy::HWY_NAMESPACE::MultiVecD<float, WC>::VectorType  VectorType;
                typedef typename  hwy::HWY_NAMESPACE::MultiVecD<float, WC>::MaskType  MaskType;
                typedef typename hwy::HWY_NAMESPACE::MultiVecD<float, WC> _D;
            };

            using TypeSelector = SmootherTypes<_lc::c_want_lane_count, _lc::c_lane_count>;

            typedef typename TypeSelector::VectorType VecType;
            typedef typename TypeSelector::MaskType VecMaskType;
        public:
            typedef typename TypeSelector::VectorType ValueType;
            typedef typename TypeSelector::MaskType  MaskType;

            class ISmoothValueConverter
            {
            public:
                virtual T Convert() const = 0;

                HWY_INLINE void SetLane(int l) { lane_ = l;}
            protected:
                int lane_ = 0;
            };

            template<typename I>
            class SmoothValueConverterTplt : public ISmoothValueConverter
            {
            public:
                HWY_INLINE SmoothValueConverterTplt() : data_(NULL)
                {}

                HWY_INLINE SmoothValueConverterTplt(const std::atomic<I> * val) : data_(val)
                {}

                HWY_INLINE  void SetData(const std::atomic<I> * val)
                {
                    data_ = val;
                }

                HWY_ATTR HWY_INLINE  I GetSourceValue() const
                {
                    return data_->load(std::memory_order_acquire);
                }

            protected:
                const std::atomic<I> * data_;
            };

            static constexpr size_t ValueCount()
            {
                return COUNT;
            }


            HWY_ATTR HWY_INLINE HighwayValueSmoother() : zeroCurrentCountdown_(0)
            {
                constexpr size_t allocsz = AllocSize();

                if(!targetVals_)
                    targetVals_ = hwy::AllocateAligned<float>(allocsz);

                if(!currentVals_)
                    currentVals_ = hwy::AllocateAligned<float>(allocsz);
            }

            HWY_ATTR HWY_INLINE HighwayValueSmoother(T smoothVal) : zeroCurrentCountdown_(0)
            {
                constexpr size_t allocsz = AllocSize();

                if(!targetVals_)
                    targetVals_ = hwy::AllocateAligned<float>(allocsz);

                if(!currentVals_)
                    currentVals_ = hwy::AllocateAligned<float>(allocsz);

                configure(smoothVal);
            }

            ~HighwayValueSmoother() = default;

            template<typename... ATOMIC>
            HWY_ATTR HWY_INLINE void initialise(ATOMIC... args)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                InitFunc<ATOMIC...>::initTargets(targets_, args...);
            }

            template<typename... ARGS>
            HWY_ATTR HWY_INLINE void SetSmooth(ARGS... smoothVals)
            {
                configure(smoothVals...);
            }

            HWY_ATTR HWY_INLINE void SetSmooth(T smoothVal)
            {
                configure(smoothVal);
            }

            HWY_ATTR HWY_INLINE void UpdateTargetValues()
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const TypeSelector::_D _vectype;

                VecType val = HWY::Zero(_vectype);
                VecMaskType mask = HWY::Not(_vectype, HWY::MaskFalse(_vectype));
                constexpr size_t allocsz = AllocSize();

                for(size_t x=0; x < COUNT; ++x)
                {
                    T curval = targets_[x].load();

                    val = HWY::MaskedSetOr(_vectype, val, mask, curval);
                    mask = HWY::SlideMask1Up(_vectype, mask);
                }

                frozen_ = false;
                HWY::Store(val, _vectype, targetVals_.get());
            }

            HWY_ATTR HWY_INLINE void PrepareCurrentValues()
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const TypeSelector::_D _vectype;

                VecType val = HWY::Zero(_vectype);
                VecMaskType mask = HWY::Not(_vectype, HWY::MaskFalse(_vectype));
                constexpr size_t allocsz = AllocSize();

                for(size_t x=0; x < COUNT; ++x)
                {
                    T curval = targets_[x].load();

                    val = HWY::MaskedSetOr(_vectype, val, mask, curval);
                    mask = HWY::SlideMask1Up(_vectype, mask);
                }

                frozen_ = false;
                HWY::Store(val, _vectype, currentVals_.get());
            }

            
            HWY_ATTR HWY_INLINE void ZeroCurrentValues()
            {
                constexpr size_t allocsz = AllocSize();
                if(currentVals_)
                    memset(currentVals_.get(),0, allocsz * sizeof(float));

                frozen_ = false;
            }

            HWY_ATTR HWY_INLINE void ZeroCurrentValueAtIndex(size_t index)
            {
                constexpr size_t allocsz = AllocSize();
                if(currentVals_ && (index < allocsz))
                    currentVals_[index] = 0;
            }

            template<typename X>
            HWY_ATTR HWY_INLINE void SetCurrentValues(const X * values, size_t from, size_t count)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const TypeSelector::_D  _vectype;

                const  size_t end = ((count + from) > COUNT) ? COUNT : (count + from);

                VecType current = HWY::Load(_vectype, currentVals_.get());
                for(size_t c=from; c < end; ++c)
                {
                    current = HWY::InsertLane( _vectype, current,  c, values[c - from]);
                }

                HWY::Store(current, _vectype, currentVals_.get());
            }


            HWY_ATTR HWY_INLINE void ZeroTargetValues()
            {
                constexpr size_t allocsz = AllocSize();
                if(targetVals_)
                    memset(targetVals_.get(),0, allocsz * sizeof(float));

                frozen_ = false;
            }

            HWY_ATTR HWY_INLINE void Start(VecType & target, VecType & current, VecType & smooth  ) const
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const TypeSelector::_D _vectype;

                target = HWY::Load(_vectype, targetVals_.get());
                current = HWY::Load(_vectype, currentVals_.get());
                smooth = HWY::Load(_vectype, smooth_.get());
            }

            HWY_ATTR HWY_INLINE void End(const VecType & current) const
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const TypeSelector::_D _vectype;

                HWY::Store(current, _vectype, currentVals_.get());
            }

            template<typename OT, typename... OUT>
            HWY_ATTR HWY_INLINE void Run(const size_t numTimes, const VecType & smooth, const VecType & target, VecType & current, OT & out1,  OUT&... output)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const TypeSelector::_D _vectype;
                const HWY::DFromV<OT> _outtype;
                using OutMaskType = hwy::HWY_NAMESPACE::MFromD< hwy::HWY_NAMESPACE::DFromV<OT>>;
                OutMaskType outMask = HWY::Not(HWY::MaskFalse(_outtype));
                
                if(frozen_)
                {
                    //Return the values from last time. No point in running the calculations if the outcome will not change
                    GetOutput(outMask, current, out1, output...);
                    return;
                }
                 
                VecType newValues;
                const VecMaskType laneMask = HWY::FirstN(_vectype, static_cast<int>(COUNT));
    
                for(size_t lane=0; lane < numTimes; ++lane)
                {
                   // newValues  =  HWY::MulAdd(HWY::Sub(target, current), smooth, current);
                    newValues = HWY::Sub(_vectype, target, current);
                    newValues = HWY::Mul(_vectype, newValues, smooth);
                    newValues = HWY::Add(_vectype, current, newValues);

                    if((lane > 0) && HWY::AllFalse(_vectype, HWY::MaskedNe(_vectype, laneMask, newValues, current)))
                    {
                        //If we're here, then the target and current state values are no longer moving.
                        //Thus, it is safe to skip the calculation for the remainder of the lanes - since
                        //the broadcast(s) would have set the remainder of the lanes already.
                        //It does mean the broadcasts need running at least once, so only skip if lane > 0
                        frozen_ = true;
                        break;
                    }

                    current = newValues;
                    GetOutput(outMask, newValues, out1, output...);
                    outMask = HWY::SlideMask1Up(_outtype, outMask);
                }
            }

         
            HWY_INLINE bool IsFrozen() const
            {
                return frozen_;
            }

        private:

            enum TargetType
            {
                TargetType_Atmoic,
                TargetType_Conversion
            };

            struct Target
            {
                TargetType type;
                union
                {
                    const std::atomic<T> * atomic;
                    ISmoothValueConverter * conv;
                } data;

                HWY_ATTR HWY_INLINE T load() const
                {
                    switch(type)
                    {
                        case TargetType_Atmoic:
                            return data.atomic->load(std::memory_order_acquire);

                        case TargetType_Conversion:
                            return data.conv->Convert();
                    }

                    return 0;
                }
            };


            HWY_API constexpr size_t  AllocSize()
            {
                return  _lc::c_max_lane_count;
            }
            
            template<typename X, typename... ARGS> 
            HWY_ATTR HWY_INLINE void configure(X a1, ARGS... args)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                constexpr size_t allocsz = AllocSize();

                 if(!smooth_)
                    smooth_ = hwy::AllocateAligned<float>(allocsz);

                 smooth_[0] = a1;
                 int idx = 1;
                 for(const auto p : {args...})
                 {
                     smooth_[idx] = p;
                     ++idx;
                 }

                frozen_ = false;
            }

            HWY_ATTR HWY_INLINE void configure(T smoothval)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const TypeSelector::_D _vectype;
                constexpr size_t allocsz = AllocSize();

                if(!smooth_)
                    smooth_ = hwy::AllocateAligned<float>(allocsz);

                frozen_ = false;
                HWY::Store(HWY::Set(_vectype, smoothval), _vectype, smooth_.get());
            }

            template<typename... X>
            struct InitFunc
            {
                
                template<typename A>
                HWY_API void SetTarget(int & idx, Target *  dest,  const std::atomic<A> * a)
                {
                    dest[idx].type = TargetType_Atmoic;
                    dest[idx].data.atomic = a;
                    ++idx;
                }

                HWY_API void SetTarget(int & idx, Target *  dest,   ISmoothValueConverter * conv)
                {
                    dest[idx].type = TargetType_Conversion;
                    dest[idx].data.conv = conv;
                    conv->SetLane(idx);
                    ++idx;
                }

                template<int C=COUNT, std::size_t N = sizeof...(X)>
                HWY_API void initTargets(Target *  dest, X... args, 
                                         typename std::enable_if< (C == N), void>::type * = nullptr)
                {
                    int idx = 0;

                    //Call 'SetTarget' once for every paramter in 'args...', which will increment 'idx'
                    (SetTarget(idx, dest, args), ...);
                }
            };

            //Get
            template<int IDX, typename MT, typename X, int FLAG = ADD_FLAG>
            HWY_API void GetOutputValue(const MT & mask, const X & convstate, X & ov,
                                        typename std::enable_if< (((FLAG >> IDX) & 1) == 0) , void>::type * = nullptr)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                ov =  HWY::IfThenElse(mask, HWY::BroadcastLane<IDX>(convstate), ov);
            }


            //Additive
            template<int IDX, typename MT, typename X, int FLAG = ADD_FLAG>
            HWY_API void GetOutputValue(const MT & mask, const X & convstate, X & ov,
                                        typename std::enable_if< (((FLAG >> IDX) & 1) == 1) , void>::type * = nullptr)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                ov = HWY::MaskedAddOr(ov, mask, ov, HWY::BroadcastLane<IDX>(convstate));
            }


            template<typename MT, typename VT, typename OT>
            HWY_API void GetOutput(const MT & mask, VT & state, OT & v1)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const HWY::DFromV<OT> _outtype;
                const TypeSelector::_D _vectype;

                const OT x = HWY::ResizeBitCast(_vectype, _outtype, state);
                GetOutputValue<0>(mask, x, v1);
            }

            template<typename MT, typename VT, typename OT>
            HWY_API void GetOutput(const MT & mask, VT & state, OT & v1, OT & v2)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const HWY::DFromV<OT> _outtype;
                const TypeSelector::_D _vectype;

                const OT x = HWY::ResizeBitCast(_vectype, _outtype, state);
                GetOutputValue<0>(mask, x, v1);
                GetOutputValue<1>(mask, x, v2);
            }

            template<typename MT, typename VT, typename OT>
            HWY_API void GetOutput(const MT & mask, VT & state, OT & v1, OT & v2, OT & v3)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const HWY::DFromV<OT> _outtype;
                const TypeSelector::_D _vectype;

                const OT x = HWY::ResizeBitCast(_vectype, _outtype, state);
                GetOutputValue<0>(mask, x, v1);
                GetOutputValue<1>(mask, x, v2);
                GetOutputValue<2>(mask, x, v3);
            }

            template<typename MT, typename VT, typename OT>
            HWY_API void GetOutput(const MT & mask, VT & state, OT & v1, OT & v2, OT & v3, OT & v4)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const HWY::DFromV<OT> _outtype;
                const TypeSelector::_D _vectype;
               
                const OT x = HWY::ResizeBitCast(_vectype, _outtype, state);
                GetOutputValue<0>(mask, x, v1);
                GetOutputValue<1>(mask, x, v2);
                GetOutputValue<2>(mask, x, v3);
                GetOutputValue<3>(mask, x, v4);
            }

            template<typename MT, typename VT, typename OT>
            HWY_API void GetOutput(const MT & mask, VT & state, OT & v1, OT & v2, OT & v3, OT & v4, OT & v5)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const HWY::DFromV<OT> _outtype;
                const TypeSelector::_D _vectype;

                //Cast to larger output type, and then broadcast
                OT x = HWY::ResizeBitCast(_vectype, _outtype, state);
                GetOutputValue<0>(mask, x, v1);
                GetOutputValue<1>(mask, x, v2);
                GetOutputValue<2>(mask, x, v3);
                GetOutputValue<3>(mask, x, v4);
            #if HWY_MIN_BYTES > 16
                GetOutputValue<4>(mask, x, v5);
            #else
                x =HWY::ResizeBitCast(_vectype, _outtype, HWY::SlideDownLanes(_vectype, state, 4));
                GetOutputValue<0>(mask, x, v5);
            #endif
            }

            template<typename MT, typename VT, typename OT>
            HWY_API void GetOutput(const MT & mask, VT & state, OT & v1, OT & v2, OT & v3, OT & v4, OT & v5, OT & v6)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const HWY::DFromV<OT> _outtype;
                const TypeSelector::_D _vectype;

                //Cast to larger output type, and then broadcast
                const OT x = HWY::ResizeBitCast(_vectype, _outtype, state);
                GetOutputValue<0>(mask, x, v1);
                GetOutputValue<1>(mask, x, v2);
                GetOutputValue<2>(mask, x, v3);
                GetOutputValue<3>(mask, x, v4);

            #if HWY_MIN_BYTES > 16
                GetOutputValue<4>(mask, x, v5);
                GetOutputValue<5>(mask, x, v6);
            #else
                x =HWY::ResizeBitCast(_vectype, _outtype, HWY::SlideDownLanes(_vectype, state, 4));
                GetOutputValue<0>(mask, x, v5);
                GetOutputValue<1>(mask, x, v6);
            #endif
            }

            template<typename MT, typename VT, typename OT>
            HWY_API void GetOutput(const MT & mask, VT & state, OT & v1, OT & v2, OT & v3, OT & v4, OT & v5, OT & v6, OT & v7, OT & v8)
            {
                namespace HWY = hwy::HWY_NAMESPACE;
                const HWY::DFromV<OT> _outtype;
                const TypeSelector::_D _vectype;

                //Cast to larger output type, and then broadcast
                OT x = HWY::ResizeBitCast(_vectype, _outtype, state);
                GetOutputValue<0>(mask, x, v1);
                GetOutputValue<1>(mask, x, v2);
                GetOutputValue<2>(mask, x, v3);
                GetOutputValue<3>(mask, x, v4);
                
            #if HWY_MIN_BYTES > 16
                GetOutputValue<4>(mask, x, v5);
                GetOutputValue<5>(mask, x, v6);
                GetOutputValue<6>(mask, x, v7);
                GetOutputValue<7>(mask, x, v8);
            #else
                x =HWY::ResizeBitCast(_vectype, _outtype, HWY::SlideDownLanes(_vectype, state, 4));
                GetOutputValue<0>(mask, x, v5);
                GetOutputValue<1>(mask, x, v6);
                GetOutputValue<2>(mask, x, v7);
                GetOutputValue<3>(mask, x, v8);
            #endif
            }
            
            int zeroCurrentCountdown_;
            bool frozen_ = false; //when values will no logner change - there is no need to do anymore processing
            hwy::AlignedFreeUniquePtr<float[]> smooth_;
            hwy::AlignedFreeUniquePtr<float[]> targetVals_;
            hwy::AlignedFreeUniquePtr<float[]> currentVals_;
            Target targets_[COUNT];
        };
    }
}  // namespace hwy
HWY_AFTER_NAMESPACE();
