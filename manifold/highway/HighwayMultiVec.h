

namespace hwy
{
    namespace HWY_NAMESPACE
    {
        //Default - compile error
        template<typename T, int N, typename ENABLE = void>
        struct MultiVecType
        {
        };

    //=====================================================================================================
    //If the number of lanes requested can fit in a single vector
    #if HWY_HAVE_CONSTEXPR_LANES
        
        //Utility to get number of lanes without needing D variables
        //For use in default template args
        template<typename T>
        struct __MVLaneCounter
        {
            static constexpr size_t NumLanes()
            {
                hwy::HWY_NAMESPACE::ScalableTag<T> __vtype;
                return hwy::HWY_NAMESPACE::Lanes(__vtype);
            }
        };
    #else
       
        template<typename T>
        struct __MVLaneCounter
        {
            //NumLanes not constant and is unknown at compile time
            //Use the minimum bytes, since the number of usable lanes on SVE can vary - at least the minimum is guaranteed 
            static constexpr size_t NumLanes()
            {
                return (HWY_MIN_BYTES / sizeof(T));
            }
        };

    #endif
        template<typename T, int N>
        struct MultiVecType<T,N, hwy::EnableIf<N <= __MVLaneCounter<T>::NumLanes() >>
        {
            using __VectorD = hwy::HWY_NAMESPACE::ScalableTag<T>;
            using VectorType = hwy::HWY_NAMESPACE::VFromD<__VectorD >;
            using VectorMaskType = hwy::HWY_NAMESPACE::MFromD<__VectorD >;
            typedef T BaseType;

            static HWY_ATTR HWY_INLINE  VectorType Add(const VectorType & a, const VectorType & b)
            {
                return hwy::HWY_NAMESPACE::Add(a, b);
            }


            static HWY_ATTR HWY_INLINE  bool AllFalse(const VectorMaskType & m)
            {
                const __VectorD  _vectype;
                constexpr size_t multivecLanes = N;
                const size_t lanes = hwy::HWY_NAMESPACE::Lanes(_vectype);

                VectorMaskType x = m;
                if(multivecLanes  < lanes)
                    x =  hwy::HWY_NAMESPACE::And(m, hwy::HWY_NAMESPACE::FirstN(_vectype, multivecLanes));

                 
                return hwy::HWY_NAMESPACE::AllFalse(_vectype, x);
            }

            template<int L>
            static HWY_ATTR HWY_INLINE VectorType BroadcastLane(const VectorType & v)
            {
                return hwy::HWY_NAMESPACE::BroadcastLane<L>(v);
            }
    
            static HWY_ATTR HWY_INLINE  VectorMaskType FirstN(const size_t n)
            {
                const __VectorD  _vectype;
                constexpr size_t multivecLanes = N;
                if(n >= multivecLanes)
                    return hwy::HWY_NAMESPACE::Not(hwy::HWY_NAMESPACE::MaskFalse(_vectype));

                return  hwy::HWY_NAMESPACE::FirstN(_vectype, n);
            }

            static HWY_ATTR HWY_INLINE  VectorType IfThenElse(const VectorMaskType & m, const VectorType & t, const VectorType & f)
            {
                return  hwy::HWY_NAMESPACE::IfThenElse(m,t,f);
            }

            static HWY_ATTR HWY_INLINE  VectorType InsertLane(const VectorType & v, const size_t lane, const BaseType val)
            {
                return hwy::HWY_NAMESPACE::InsertLane(v, lane, val);
            }

            static HWY_ATTR HWY_INLINE VectorType Load(const T * ptr)
            {
                const __VectorD  _vectype;
                return  hwy::HWY_NAMESPACE::Load(_vectype, ptr);
            }

            static HWY_ATTR HWY_INLINE  VectorMaskType MaskFalse()
            {
                const __VectorD  _vectype;
                return  hwy::HWY_NAMESPACE::MaskFalse(_vectype);
            }

            static HWY_ATTR HWY_INLINE VectorMaskType MaskedNe(const VectorMaskType & m, const VectorType & a, const VectorType & b)
            {
                return  hwy::HWY_NAMESPACE::MaskedNe(m,a,b);
            }

            static HWY_ATTR HWY_INLINE  VectorType Mul(const VectorType & a, const VectorType & b)
            {
                return hwy::HWY_NAMESPACE::Mul(a, b);
            }

            static HWY_ATTR HWY_INLINE VectorMaskType Not(const VectorMaskType & m)
            {
                return  hwy::HWY_NAMESPACE::Not(m);
            }

            static HWY_ATTR HWY_INLINE VectorType MaskedSetOr(const VectorType & v, const VectorMaskType & m, const T val)
            {
                return  hwy::HWY_NAMESPACE::MaskedSetOr(v, m, val);
            }

            template<typename SRCTYPE>
            static HWY_ATTR HWY_INLINE VectorType ResizeBitCastFrom(const SRCTYPE & v)
            {
                const __VectorD  _vectype;
                return  hwy::HWY_NAMESPACE::ResizeBitCast(_vectype, v);
            }

            template<typename DESTTYPE>
            static HWY_ATTR HWY_INLINE DESTTYPE ResizeBitCastTo(const VectorType & v)
            {
                const hwy::HWY_NAMESPACE::DFromV<DESTTYPE> _desttype;
                return  hwy::HWY_NAMESPACE::ResizeBitCast(_desttype, v);
            }

            static HWY_ATTR HWY_INLINE VectorType Set(const BaseType val)
            {
                const __VectorD  _vectype;
                return  hwy::HWY_NAMESPACE::Set(_vectype, val);
            }

            static HWY_ATTR HWY_INLINE VectorType SlideDownLanes(const VectorType & x, size_t n)
            {
                const __VectorD  _vectype;
                constexpr size_t multivecLanes = N;
                const size_t numLanes = hwy::HWY_NAMESPACE::Lanes(_vectype);

                if(n >= multivecLanes)
                    return Zero();

                VectorType ret =  hwy::HWY_NAMESPACE::SlideDownLanes(_vectype, x, n);
                if(multivecLanes < numLanes)
                {
                    //Zero additional lanes
                    VectorType mask = hwy::HWY_NAMESPACE::VecFromMask(hwy::HWY_NAMESPACE::FirstN(_vectype, multivecLanes - n));
                    ret = hwy::HWY_NAMESPACE::And(ret, mask);
                }

                return ret;
            }

            static HWY_ATTR HWY_INLINE VectorType SlideUpLanes(const VectorType & x, size_t n)
            {
                const __VectorD  _vectype;
                return hwy::HWY_NAMESPACE::SlideUpLanes(_vectype, x,n);
            }

            static HWY_ATTR HWY_INLINE  VectorMaskType   SlideMask1Up(const VectorMaskType & m)
            {
                const __VectorD  _vectype;
                return hwy::HWY_NAMESPACE::SlideMask1Up(_vectype, m);
            }

            static HWY_ATTR HWY_INLINE  VectorType Sub(const VectorType & a, const VectorType & b)
            {
                return hwy::HWY_NAMESPACE::Sub(a, b);
            }

            template<class I, class O, 
                        int IN  = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<I>),
                        int ON = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<O>),
                        int STN = __MVLaneCounter<BaseType>::NumLanes()  >
             static HWY_ATTR HWY_INLINE void TableLookupLanes(const VectorType & v, const I & idx,  O & out,
                                                              typename std::enable_if< ((STN==IN) && (ON == IN)), void>::type * = nullptr)
            {
                 const hwy::HWY_NAMESPACE::DFromV<I> _indtype;
                 const hwy::HWY_NAMESPACE::DFromV<O> _outtype;

                 auto indicies = hwy::HWY_NAMESPACE::IndicesFromVec(_indtype, idx);

                 const I result = hwy::HWY_NAMESPACE::TableLookupLanes(hwy::HWY_NAMESPACE::BitCast(_indtype, v), indicies);

                 out = hwy::HWY_NAMESPACE::BitCast(_outtype,  result);
            }

            static HWY_ATTR HWY_INLINE void Store(T * ptr, const VectorType & v)
            {
                const __VectorD  _vectype;
                hwy::HWY_NAMESPACE::Store(v,_vectype, ptr);
            }

            static HWY_ATTR HWY_INLINE VectorType Zero()
            {
                const __VectorD  _vectype;
                return  hwy::HWY_NAMESPACE::Zero(_vectype); 
            }

        };

    //=====================================================================================================
    //If the number of lanes requested can fit in a two vectors
        template<typename T, int N>
        struct MultiVecType<T,N,
                            hwy::EnableIf< (N > __MVLaneCounter<T>::NumLanes()) && (N <= (__MVLaneCounter<T>::NumLanes() * 2)) >> 
        {
            using __SubTypeD = hwy::HWY_NAMESPACE::ScalableTag<T>;
            using __SubType = hwy::HWY_NAMESPACE::VFromD<__SubTypeD>;
            using __SubMaskType = hwy::HWY_NAMESPACE::MFromD<__SubTypeD>;
            using VectorType = hwy::HWY_NAMESPACE::Vec2<__SubTypeD>; //Not D - D is not available!
            using VectorMaskType = VectorType; //No mask type, so use the vector type
            typedef T BaseType;
         
            static HWY_ATTR HWY_INLINE  VectorType Add(const VectorType & a, const VectorType & b)
            {
                const __SubTypeD _subtype;
                return hwy::HWY_NAMESPACE::Create2(_subtype,
                                                   hwy::HWY_NAMESPACE::Add(hwy::HWY_NAMESPACE::Get2<0>(a), hwy::HWY_NAMESPACE::Get2<0>(b)),
                                                   hwy::HWY_NAMESPACE::Add(hwy::HWY_NAMESPACE::Get2<1>(a), hwy::HWY_NAMESPACE::Get2<1>(b)));
            }

            static HWY_ATTR HWY_INLINE  bool AllFalse(const VectorMaskType & m)
            {
                constexpr size_t myLaneCount = N;
                const __SubTypeD _subtype;

                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);

                bool res = true;

                if(myLaneCount > subLaneCount)
                {
                    res = hwy::HWY_NAMESPACE::AllFalse(_subtype, hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<0>(m)));  

                    __SubMaskType x = hwy::HWY_NAMESPACE::FirstN(_subtype, myLaneCount - subLaneCount);
                    x = hwy::HWY_NAMESPACE::And(x, hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<1>(m)));
                    res &= hwy::HWY_NAMESPACE::AllFalse(_subtype, x);
                }
                else if(myLaneCount == subLaneCount)
                {
                    res = hwy::HWY_NAMESPACE::AllFalse(_subtype, hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<0>(m)));  
                }
                else  //mylaneCount < subLaneCount
                {
                    __SubMaskType x = hwy::HWY_NAMESPACE::FirstN(_subtype, myLaneCount);
                    x = hwy::HWY_NAMESPACE::And(x, hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<0>(m)));
                    res = hwy::HWY_NAMESPACE::AllFalse(_subtype, x);
                }
               
                return res;
            }

            template<int L>
            static HWY_ATTR HWY_INLINE VectorType BroadcastLane(const VectorType & v)
            {
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);

                __SubType v0;

                if(L < subLaneCount)
                {
                    v0 = hwy::HWY_NAMESPACE::BroadcastLane<0>(hwy::HWY_NAMESPACE::SlideDownLanes(_subtype,  hwy::HWY_NAMESPACE::Get2<0>(v), L))  ;
                }
                else 
                {
                #if HWY_HAVE_CONSTEXPR_LANES
                    v0 = hwy::HWY_NAMESPACE::BroadcastLane<L - hwy::HWY_NAMESPACE::Lanes(_subtype)>(hwy::HWY_NAMESPACE::Get2<1>( v));
                #else
                    v0 = hwy::HWY_NAMESPACE::BroadcastLane<0>(hwy::HWY_NAMESPACE::SlideDownLanes(_subtype, hwy::HWY_NAMESPACE::Get2<1>(v), L - subLaneCount));
                #endif
                }

                return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v0);
            }

            static HWY_ATTR HWY_INLINE VectorMaskType FirstN(size_t n)
            {
                constexpr size_t myLaneCount = N;
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);

                __SubMaskType subtypemskval0;
                __SubMaskType subtypemskval1;

                if(n >= myLaneCount)
                {
                    //Set all lanes to true
                    subtypemskval0 = hwy::HWY_NAMESPACE::Not(hwy::HWY_NAMESPACE::MaskFalse(_subtype));
                    subtypemskval1 = subtypemskval0;
                }
                else if(n > subLaneCount)
                {
                    subtypemskval0 =  hwy::HWY_NAMESPACE::Not( hwy::HWY_NAMESPACE::MaskFalse(_subtype)); 
                    subtypemskval1 =  hwy::HWY_NAMESPACE::FirstN(_subtype, n - subLaneCount  ); 
                }
                else if(n != 0)
                {
                    subtypemskval0 = hwy::HWY_NAMESPACE::FirstN( _subtype, n); 
                    subtypemskval1 = hwy::HWY_NAMESPACE::MaskFalse(_subtype);
                }
                else
                {
                    subtypemskval0 = hwy::HWY_NAMESPACE::MaskFalse(_subtype);
                    subtypemskval1 = subtypemskval0;
                }

                return hwy::HWY_NAMESPACE::Create2(_subtype, hwy::HWY_NAMESPACE::VecFromMask(subtypemskval0), 
                                                             hwy::HWY_NAMESPACE::VecFromMask(subtypemskval1));
            }

            static HWY_ATTR HWY_INLINE  VectorType IfThenElse(const VectorMaskType & m, const VectorType & t, const VectorType & f)
            {
                //We know there are two vectors - we don't care too much about if what parts of each one are important or ignored.
                
                const __SubTypeD _subtype;

                const __SubMaskType subtypemskval0 = hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<0>(m));
                const __SubMaskType subtypemskval1 = hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<1>(m));
                __SubType v0, v1;
                
                v0 = hwy::HWY_NAMESPACE::IfThenElse(subtypemskval0, hwy::HWY_NAMESPACE::Get2<0>(t), hwy::HWY_NAMESPACE::Get2<0>(f));
                v1 = hwy::HWY_NAMESPACE::IfThenElse(subtypemskval1, hwy::HWY_NAMESPACE::Get2<1>(t), hwy::HWY_NAMESPACE::Get2<1>(f));

                return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v1);
            }

            static HWY_ATTR HWY_INLINE  VectorType InsertLane(const VectorType & v, const size_t lane, const BaseType val)
            {
                 const __SubTypeD _subtype;
                 const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                 __SubType v0, v1;

                 if(lane < subLaneCount)
                 {
                     v1 = hwy::HWY_NAMESPACE::Get2<1>(v);
                     v0 = hwy::HWY_NAMESPACE::InsertLane(hwy::HWY_NAMESPACE::Get2<0>(v), lane, val);
                 }
                 else //if(lane >= subLaneCount)
                 {
                     v0 = hwy::HWY_NAMESPACE::Get2<0>(v);
                     v1 = hwy::HWY_NAMESPACE::InsertLane(hwy::HWY_NAMESPACE::Get2<1>(v), subLaneCount - lane, val);
                 }

                 return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v1);
            }

            static HWY_ATTR HWY_INLINE VectorType Load(const T * ptr)
            {
                constexpr size_t myLaneCount = N;
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                const size_t maxLanes = subLaneCount * 2;

                __SubType v0, v1;

                if(myLaneCount >= maxLanes)
                {
                     v0 = hwy::HWY_NAMESPACE::Load(_subtype, ptr);
                     v1 = hwy::HWY_NAMESPACE::Load(_subtype, ptr + subLaneCount);
                }
                else if(myLaneCount > subLaneCount)
                {
                    v0 = hwy::HWY_NAMESPACE::Load(_subtype, ptr);
                    v1 = hwy::HWY_NAMESPACE::LoadN(_subtype, ptr + subLaneCount,   myLaneCount - subLaneCount);
                }
                else if(myLaneCount == subLaneCount)
                {
                    v0 = hwy::HWY_NAMESPACE::Load(_subtype, ptr);
                    v1 = hwy::HWY_NAMESPACE::Zero(_subtype);
                }
                else //myLaneCount < subLaneCount
                {
                    v0 = hwy::HWY_NAMESPACE::LoadN(_subtype, ptr, myLaneCount);
                    v1 = hwy::HWY_NAMESPACE::Zero(_subtype);
                }

                return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v1);
            }

            static HWY_ATTR HWY_INLINE  VectorMaskType MaskFalse()
            {
                return Zero();
            }

            static HWY_ATTR HWY_INLINE  VectorMaskType MaskedNe(const VectorMaskType & m, const VectorType & a, const VectorType & b)
            {
                constexpr size_t myLaneCount = N;
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                const size_t maxLanes = subLaneCount * 2;

                __SubMaskType subtypemskval0;
                __SubMaskType subtypemskval1;
                
                
                subtypemskval0 = hwy::HWY_NAMESPACE::MaskedNe(hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<0>(m)),
                                                                hwy::HWY_NAMESPACE::Get2<0>(a),
                                                                hwy::HWY_NAMESPACE::Get2<0>(b));

                subtypemskval1 = hwy::HWY_NAMESPACE::MaskedNe(hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<1>(m)),
                                                                hwy::HWY_NAMESPACE::Get2<1>(a),
                                                                hwy::HWY_NAMESPACE::Get2<1>(b));
                
                return hwy::HWY_NAMESPACE::Create2(_subtype, hwy::HWY_NAMESPACE::VecFromMask(subtypemskval0), 
                                                             hwy::HWY_NAMESPACE::VecFromMask(subtypemskval1));
            }

            static HWY_ATTR HWY_INLINE VectorType MaskedSetOr(const VectorType & v, const VectorMaskType & m, const T val)
            {
                const __SubTypeD _subtype;
                __SubType v0;
                __SubType v1;
                
                const __SubType  x = hwy::HWY_NAMESPACE::Set(_subtype, val);
                
                __SubType mask = hwy::HWY_NAMESPACE::Get2<0>(m);
                v0 = hwy::HWY_NAMESPACE::IfThenElse( hwy::HWY_NAMESPACE::MaskFromVec(mask), x, hwy::HWY_NAMESPACE::Get2<0>(v));
               
                mask = hwy::HWY_NAMESPACE::Get2<1>(m);
                v1 = hwy::HWY_NAMESPACE::IfThenElse( hwy::HWY_NAMESPACE::MaskFromVec(mask), x, hwy::HWY_NAMESPACE::Get2<1>(v));

                return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v1);
            }

            
            static HWY_ATTR HWY_INLINE  VectorType Mul(const VectorType & a, const VectorType & b)
            {
                const __SubTypeD _subtype;
                return hwy::HWY_NAMESPACE::Create2(_subtype,
                                                   hwy::HWY_NAMESPACE::Mul(hwy::HWY_NAMESPACE::Get2<0>(a), hwy::HWY_NAMESPACE::Get2<0>(b)),
                                                   hwy::HWY_NAMESPACE::Mul(hwy::HWY_NAMESPACE::Get2<1>(a), hwy::HWY_NAMESPACE::Get2<1>(b)));
            }

            static HWY_ATTR HWY_INLINE VectorMaskType Not(const VectorMaskType & m)
            {
                const __SubTypeD _subtype;
                return hwy::HWY_NAMESPACE::Create2(_subtype,
                                                   hwy::HWY_NAMESPACE::VecFromMask( hwy::HWY_NAMESPACE::Not(hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<0>(m)))),
                                                   hwy::HWY_NAMESPACE::VecFromMask( hwy::HWY_NAMESPACE::Not(hwy::HWY_NAMESPACE::MaskFromVec(hwy::HWY_NAMESPACE::Get2<1>(m)))));
            }

            

            template<typename SRCTYPE>
            static HWY_ATTR HWY_INLINE VectorType ResizeBitCastFrom(const SRCTYPE & v)
            {
                using __SrcD = hwy::HWY_NAMESPACE::DFromV<SRCTYPE>;
                const __SrcD _srctype;
                const size_t srcLaneCount = hwy::HWY_NAMESPACE::Lanes(_srctype);
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                
                __SubType v0, v1;

                v0 = hwy::HWY_NAMESPACE::ResizeBitCast(_subtype, v);

                if(srcLaneCount <= subLaneCount)
                {
                    v1 = hwy::HWY_NAMESPACE::Zero(_subtype);
                }
                else //srcLaneCount > subLameCount
                {
                    v1 = hwy::HWY_NAMESPACE::ResizeBitCast(_subtype, hwy::HWY_NAMESPACE::SlideDownLanes(_srctype, v, subLaneCount));
                }

                return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v1);
            }

            template<typename DESTTYPE>
            static HWY_ATTR HWY_INLINE DESTTYPE ResizeBitCastTo(const VectorType & v)
            {
                using _DestD = hwy::HWY_NAMESPACE::DFromV<DESTTYPE>;
                constexpr size_t myLaneCount = N;
                const _DestD _desttype;
                const size_t destLaneCount = hwy::HWY_NAMESPACE::Lanes(_desttype);
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                
                DESTTYPE ret, tmp;
                
                ret = hwy::HWY_NAMESPACE::ResizeBitCast(_desttype, hwy::HWY_NAMESPACE::Get2<0>(v));

                if(destLaneCount > subLaneCount)
                {
                    tmp = hwy::HWY_NAMESPACE::ResizeBitCast(_desttype, hwy::HWY_NAMESPACE::Get2<1>(v));
                    tmp = hwy::HWY_NAMESPACE::SlideUpLanes(_desttype, tmp, subLaneCount);
                    ret = hwy::HWY_NAMESPACE::IfThenElse(hwy::HWY_NAMESPACE::FirstN(_subtype, subLaneCount), ret, tmp);
                }
                
                return ret;
            }

            static HWY_ATTR HWY_INLINE VectorType Set(const BaseType val)
            {
                const __SubTypeD _subtype;
                const __SubType x = hwy::HWY_NAMESPACE::Set(_subtype, val);
                return hwy::HWY_NAMESPACE::Create2(_subtype, x, x);
            }

            static HWY_ATTR HWY_INLINE VectorType SlideDownLanes(const VectorType & x, size_t n)
            {   
                if(n == 0)
                    return x;
                
                constexpr size_t myLaneCount = N;
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                __SubType v0, v1, tmp;
                
                if(n >= myLaneCount)
                {
                    v1 = hwy::HWY_NAMESPACE::Zero(_subtype);
                    v0 = v1;
                }
                else if(myLaneCount <= subLaneCount)
                {
                    //All lanes are in one vector - zero the top vector
                    v1 = hwy::HWY_NAMESPACE::Zero(_subtype);

                    v0 = hwy::HWY_NAMESPACE::Get2<0>(x);
                    v0 = hwy::HWY_NAMESPACE::SlideDownLanes(_subtype, v0, n);
                }
                else
                {
                    const size_t topSublaneCount = myLaneCount - subLaneCount;

                     //Lanes are split between v0 and v1
                    if(n < subLaneCount)
                    {
                        v0 = hwy::HWY_NAMESPACE::Get2<0>(x);
                        v0 =  hwy::HWY_NAMESPACE::SlideDownLanes(_subtype, v0, n);
                        
                        tmp =  hwy::HWY_NAMESPACE::Get2<1>(x);
                        v1 =  hwy::HWY_NAMESPACE::SlideDownLanes(_subtype, tmp, n);

                        if(topSublaneCount != subLaneCount)
                            v1 = hwy::HWY_NAMESPACE::IfThenElse(hwy::HWY_NAMESPACE::FirstN(_subtype,topSublaneCount), v1, hwy::HWY_NAMESPACE::Zero(_subtype)); 

                        tmp = hwy::HWY_NAMESPACE::SlideUpLanes(_subtype, tmp, subLaneCount - n);
                        v0 = hwy::HWY_NAMESPACE::Or(tmp, v0);
                    }
                    else if(n == subLaneCount)
                    {
                        v0 = hwy::HWY_NAMESPACE::Get2<1>(x);
                        v1 = hwy::HWY_NAMESPACE::Zero(_subtype);

                        if(topSublaneCount != subLaneCount)
                            v0 = hwy::HWY_NAMESPACE::IfThenElse(hwy::HWY_NAMESPACE::FirstN(_subtype, topSublaneCount), v0, v1); //zero out unused lanes 
                    }
                    else
                    {
                        v1 = hwy::HWY_NAMESPACE::Zero(_subtype);
                        v0 = hwy::HWY_NAMESPACE::Get2<1>(x);
                        v0 =  hwy::HWY_NAMESPACE::SlideDownLanes(_subtype, v0, n - subLaneCount);

                        if(topSublaneCount != subLaneCount)
                            v0 = hwy::HWY_NAMESPACE::IfThenElse(hwy::HWY_NAMESPACE::FirstN(_subtype,topSublaneCount), v0, v1); //zero out unused lanes 
                    }
                }
                
                return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v1);
            }


            static HWY_ATTR HWY_INLINE VectorType SlideUpLanes(const VectorType & x, size_t n)
            {
               if(n == 0)
                    return x;
                
                constexpr size_t myLaneCount = N;
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                __SubType v0, v1, tmp;
                
                if(n >= myLaneCount)
                {
                    v1 = hwy::HWY_NAMESPACE::Zero(_subtype);
                    v0 = v1;
                }
                else if(myLaneCount <= subLaneCount)
                {
                    //All lanes are in one vector - zero the top vector
                    v1 = hwy::HWY_NAMESPACE::Zero(_subtype);
                    v0 = hwy::HWY_NAMESPACE::Get2<0>(x);
                    v0 = hwy::HWY_NAMESPACE::SlideUpLanes(_subtype, v0, n);
                }
                else
                {
                     const size_t topSublaneCount = myLaneCount - subLaneCount;
                    
                     //Lanes are split between v0 and v1
                    if(n < subLaneCount)
                    {
                        tmp = hwy::HWY_NAMESPACE::Get2<0>(x);
                        v0 = hwy::HWY_NAMESPACE::SlideUpLanes(_subtype, tmp, n);
                        v1 = hwy::HWY_NAMESPACE::SlideUpLanes(_subtype, hwy::HWY_NAMESPACE::Get2<1>(x), n);

                        tmp = hwy::HWY_NAMESPACE::SlideDownLanes(_subtype, tmp, subLaneCount - n);
                        v1 = hwy::HWY_NAMESPACE::Or(v1, tmp);
                    }
                    else if(n == subLaneCount)
                    {
                        v1 = hwy::HWY_NAMESPACE::Get2<0>(x);
                        v0 = hwy::HWY_NAMESPACE::Zero(_subtype);
                    }
                    else
                    {
                        v1 = hwy::HWY_NAMESPACE::Get2<0>(x);
                        v0 = hwy::HWY_NAMESPACE::Zero(_subtype);
                        v1 = hwy::HWY_NAMESPACE::SlideUpLanes(_subtype, v1, n - subLaneCount );
                    }
                }

                return hwy::HWY_NAMESPACE::Create2(_subtype, v0, v1);
            }

            
            static HWY_ATTR HWY_INLINE VectorMaskType  SlideMask1Up(const VectorMaskType & m)
            {
                //Mask type and vector type are the same types here
                return SlideUpLanes(m, 1);
            }

            static HWY_ATTR HWY_INLINE void Store(T * ptr, const VectorType & v)
            {
                constexpr size_t myLaneCount = N;
                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);
                const size_t maxLanes = subLaneCount * 2;

                
                if(myLaneCount >= maxLanes)
                {
                    hwy::HWY_NAMESPACE::Store(hwy::HWY_NAMESPACE::Get2<0>(v), _subtype, ptr);
                    hwy::HWY_NAMESPACE::Store(hwy::HWY_NAMESPACE::Get2<1>(v), _subtype, ptr + subLaneCount);
                }
                else if(myLaneCount > subLaneCount)
                {
                    hwy::HWY_NAMESPACE::Store(hwy::HWY_NAMESPACE::Get2<0>(v), _subtype, ptr);
                    hwy::HWY_NAMESPACE::StoreN(hwy::HWY_NAMESPACE::Get2<1>(v), _subtype, ptr + subLaneCount, myLaneCount - subLaneCount);
                }
                else if(myLaneCount == subLaneCount)
                {
                    hwy::HWY_NAMESPACE::Store(hwy::HWY_NAMESPACE::Get2<0>(v), _subtype, ptr);
                }
                else //myLaneCount < subLaneCount
                {
                    hwy::HWY_NAMESPACE::StoreN(hwy::HWY_NAMESPACE::Get2<0>(v), _subtype, ptr, myLaneCount);
                }
            }

            static HWY_ATTR HWY_INLINE  VectorType Sub(const VectorType & a, const VectorType & b)
            {
                const __SubTypeD _subtype;
                return hwy::HWY_NAMESPACE::Create2(_subtype,
                                                   hwy::HWY_NAMESPACE::Sub(hwy::HWY_NAMESPACE::Get2<0>(a), hwy::HWY_NAMESPACE::Get2<0>(b)),
                                                   hwy::HWY_NAMESPACE::Sub(hwy::HWY_NAMESPACE::Get2<1>(a), hwy::HWY_NAMESPACE::Get2<1>(b)));
            }

            static HWY_ATTR HWY_INLINE VectorType Zero()
            {
                const __SubTypeD _subtype;
                __SubType tmp = hwy::HWY_NAMESPACE::Zero(_subtype);
                return hwy::HWY_NAMESPACE::Create2(_subtype, tmp, tmp);
            }

            
            //Number of indicies and output values equal total number of lanes of our type
            template<class I, class O, 
                        int IN  = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<I>),
                        int ON = HWY_MAX_LANES_D( hwy::HWY_NAMESPACE::DFromV<O>),
                        int STN = HWY_MAX_LANES_D(__SubTypeD) >
                static HWY_ATTR HWY_INLINE void TableLookupLanes(const VectorType & v, const I & idx, O & out,
                                                                 typename std::enable_if< ((STN == IN) && (ON == IN)), void>::type * = nullptr)
            {
                const hwy::HWY_NAMESPACE::DFromV<I> _indtype;
                const hwy::HWY_NAMESPACE::DFromV<O> _outtype;
                using IMaskType = hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::DFromV<I>>;

                const __SubTypeD _subtype;
                const size_t subLaneCount = hwy::HWY_NAMESPACE::Lanes(_subtype);

                O o1, o2;

                const I iSubLaneCount = hwy::HWY_NAMESPACE::Set(_indtype, static_cast<int>(subLaneCount));
                const IMaskType gecmp = hwy::HWY_NAMESPACE::Ge(idx, iSubLaneCount);
                
                if(hwy::HWY_NAMESPACE::AllTrue(_indtype, gecmp))
                {
                     //Get bottom top of table
                    __SubType tbl = hwy::HWY_NAMESPACE::Get2<1>(v);
                    auto indicies = hwy::HWY_NAMESPACE::IndicesFromVec(_indtype, hwy::HWY_NAMESPACE::Sub(idx, iSubLaneCount));
                    o1 = hwy::HWY_NAMESPACE::BitCast(_outtype, hwy::HWY_NAMESPACE::TableLookupLanes(hwy::HWY_NAMESPACE::BitCast(_indtype, tbl), indicies));
                    out = hwy::HWY_NAMESPACE::BitCast(_outtype, hwy::HWY_NAMESPACE::BitCast(_indtype, o1));
                }
                else if(hwy::HWY_NAMESPACE::AllFalse(_indtype, gecmp))
                {
                    //Get indicies
                    auto indicies = hwy::HWY_NAMESPACE::IndicesFromVec(_indtype, idx);

                     //Get bottom half of table
                    __SubType tbl = hwy::HWY_NAMESPACE::Get2<0>(v);
                    o1 = hwy::HWY_NAMESPACE::BitCast(_outtype, hwy::HWY_NAMESPACE::TableLookupLanes(hwy::HWY_NAMESPACE::BitCast(_indtype, tbl), indicies));
                    out = hwy::HWY_NAMESPACE::BitCast(_outtype, hwy::HWY_NAMESPACE::BitCast(_indtype, o1));
                }
                else
                {
                    //Get indicies
                    auto indicies = hwy::HWY_NAMESPACE::IndicesFromVec(_indtype, idx);

                     //Get bottom half of table
                    __SubType tbl = hwy::HWY_NAMESPACE::Get2<0>(v);
                    o1 = hwy::HWY_NAMESPACE::BitCast(_outtype, hwy::HWY_NAMESPACE::TableLookupLanes(hwy::HWY_NAMESPACE::BitCast(_indtype, tbl), indicies));

                    //Get top half of table
                    tbl = hwy::HWY_NAMESPACE::Get2<1>(v);
                    indicies = hwy::HWY_NAMESPACE::IndicesFromVec(_indtype, hwy::HWY_NAMESPACE::Sub(idx, iSubLaneCount));
                    o2 = hwy::HWY_NAMESPACE::BitCast(_outtype, hwy::HWY_NAMESPACE::TableLookupLanes(hwy::HWY_NAMESPACE::BitCast(_indtype, tbl), indicies));

                    //Merge the two
                    out = hwy::HWY_NAMESPACE::BitCast(_outtype, hwy::HWY_NAMESPACE::IfThenElse(gecmp, hwy::HWY_NAMESPACE::BitCast(_indtype, o2), hwy::HWY_NAMESPACE::BitCast(_indtype, o1)));
                }
            }
        };


    //=======================================================================================================
    //Dispatch layer
        
        struct MultiVecD_Base
        {};
        
        template<typename T, int N>
        struct MultiVecD : public MultiVecD_Base
        {
            typedef MultiVecType<T, N> MultiVecFuncs;
            typedef T BaseType;
            typedef typename MultiVecFuncs::VectorType VectorType;
            typedef typename MultiVecFuncs::VectorMaskType MaskType;
            static constexpr size_t Size = N;
        };

        template<typename T, int N >
        static typename MultiVecD<T,N>::VectorType Add(const MultiVecD<T,N> & /*d*/, 
                                                        const typename MultiVecD<T,N>::VectorType & a, const typename MultiVecD<T,N>::VectorType & b)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Add(a,b); 
        }

        template<typename T, int N >
        static HWY_ATTR HWY_INLINE bool AllFalse(const MultiVecD<T,N>  & /*d*/, const typename MultiVecD<T,N>::MaskType & m)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::AllFalse(m);
        }

        template<int L, typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType BroadcastLane(const MultiVecD<T,N>  & /*d*/, const typename MultiVecD<T,N>::VectorType & v)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::BroadcastLane<L>(v);
        }
        
        template<typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::MaskType FirstN(const MultiVecD<T,N>  & /*d*/, size_t n)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::FirstN(n);
        }

        template<typename T, int N>
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType IfThenElse( const MultiVecD<T,N>  & /*d*/,
                                                                                  const typename MultiVecD<T,N>::MaskType & m, 
                                                                                  const typename MultiVecD<T,N>::VectorType & t, 
                                                                                  const typename MultiVecD<T,N>::VectorType & f)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::IfThenElse(m,t,f);
        }

        template<typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType InsertLane(const MultiVecD<T,N>  & /*d*/, 
                                                                                  const typename MultiVecD<T,N>::VectorType & v,
                                                                                  const size_t lane,
                                                                                  const T val)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::InsertLane(v,lane,val);
        }
        
        template<typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType Load( const MultiVecD<T,N> & /*d*/,  const T * ptr)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Load(ptr);
        }

        template<typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::MaskType MaskFalse(const MultiVecD<T,N> & /*d*/)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::MaskFalse();
        }

        template<typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::MaskType MaskedNe(const MultiVecD<T,N> & /*d*/, 
                                                                              const typename MultiVecD<T,N>::MaskType & mask,
                                                                              const typename MultiVecD<T,N>::VectorType & a,
                                                                              const typename MultiVecD<T,N>::VectorType & b)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::MaskedNe(mask,a,b);
        }

        template<typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::MaskType Not(const MultiVecD<T,N> & /*d*/, 
                                                                         const typename MultiVecD<T,N>::MaskType & mask)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Not(mask);
        }

        
        template<typename T, int N >
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType MaskedSetOr( const MultiVecD<T,N> & /*d*/, 
                                                                                   const typename MultiVecD<T,N>::VectorType & no, 
                                                                                   const typename MultiVecD<T,N>::MaskType & mask,
                                                                                   const T val)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::MaskedSetOr(no,mask,val);
        }

        
        template<typename T, int N >
        static typename MultiVecD<T,N>::VectorType Mul(const MultiVecD<T,N> & /*d*/, 
                                                        const typename MultiVecD<T,N>::VectorType & a, const typename MultiVecD<T,N>::VectorType & b)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Mul(a,b); 
        }

        template<typename T, int N, class DESTD>
        static HWY_ATTR HWY_INLINE hwy::HWY_NAMESPACE::VFromD<DESTD> ResizeBitCast(const MultiVecD<T,N> & srcd, const DESTD & destd, const typename MultiVecD<T,N>::VectorType & v)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::template ResizeBitCastTo<hwy::HWY_NAMESPACE::VFromD<DESTD>>(v);
        }

        template<typename SRCD, typename T, int N>
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType ResizeBitCast(const SRCD & srcd, const MultiVecD<T,N> & dstd, const hwy::HWY_NAMESPACE::VFromD<SRCD> & v)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::ResizeBitCastFrom(v);
        }

        template<typename T, int N>
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType Set(const MultiVecD<T, N> & /*d*/, T val)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Set(val);
        }

        template<typename T, int N>
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType SlideDownLanes(const  MultiVecD<T,N> & /*d*/,  const typename MultiVecD<T,N>::VectorType & v, size_t n)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::SlideDownLanes(v, n);
        }

        template<typename T, int N>
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType Slide1Down(const  MultiVecD<T,N> & /*d*/,  const typename MultiVecD<T,N>::VectorType & v)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::SlideDownLanes(v, 1);
        }

        template<typename T, int N>
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::VectorType SlideUpLanes(const  MultiVecD<T,N> & /*d*/,  const typename MultiVecD<T,N>::VectorType & v, size_t n)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::SlideUpLanes(v, n);
        }

        template<typename T, int N>
        static HWY_ATTR HWY_INLINE typename MultiVecD<T,N>::MaskType SlideMask1Up(const MultiVecD<T,N> & /*d*/,  const typename MultiVecD<T,N>::MaskType & m)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::SlideMask1Up(m);
        }

        template<typename T, int N>
        static HWY_ATTR HWY_INLINE void Store(const typename MultiVecD<T,N>::VectorType & v, const MultiVecD<T,N> & /*d*/, T * ptr  )
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Store(ptr, v);
        }

        template<typename T, int N >
        static typename MultiVecD<T,N>::VectorType Sub(const MultiVecD<T,N> & /*d*/, 
                                                       const typename MultiVecD<T,N>::VectorType & a, const typename MultiVecD<T,N>::VectorType & b)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Sub(a,b); 
        }

        template<typename T, int N, class I, class O>
        static HWY_ATTR HWY_INLINE void TableLookupLanes(const MultiVecD<T,N> & /*d*/, const typename MultiVecD<T,N>::VectorType & v, const I & idx, O & out )
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::TableLookupLanes(v, idx, out);
        }

        template<typename T, int N >
        static typename MultiVecD<T,N>::VectorType Zero(const MultiVecD<T,N> & /*d*/)
        {
            using MVF = typename MultiVecD<T, N>::MultiVecFuncs;
            return MVF::Zero(); 
        }

        //=============================================================================================
        //Highways does not have this method with a D parameter, but we need it so we can tell the difference between
        //a regular vector and a MultiVec. 
        //So if a regular vector D type is passed, then just call the regular method
        
        template<typename T, int N, int K, 
                 typename V = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE V Add(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/, const V & a, const V & b)
        {
            return  hwy::HWY_NAMESPACE::Add(a,b);
        }

        template<int L, typename T, int N, int K,
                 typename V = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE V BroadcastLane(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/, const V & v)
        {
            return hwy::HWY_NAMESPACE::BroadcastLane<L>(v);
        }

        template<typename T, int N, int K, 
                 typename V = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE V InsertLane(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/, const V & vec, const size_t lane, const T val)
        {
            return  hwy::HWY_NAMESPACE::InsertLane(vec,lane,val);
        }

        template<typename T, int N, int K, 
                 typename V = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE V Mul(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/, const V & a, const V & b)
        {
            return  hwy::HWY_NAMESPACE::Mul(a,b);
        }


        template<typename T, int N, int K, 
                 typename V = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>,
                 typename M = hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE V MaskedSetOr(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/,
                                                const V & no,
                                                const M & mask,
                                                const T val)
        {
            return  hwy::HWY_NAMESPACE::MaskedSetOr(no, mask, val);
        }
        
        template<typename T, int N, int K, 
                 typename V = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>,
                 typename M = hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE M MaskedNe(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/,
                                               const M & mask, const V & a, const V & b )
        {
            return  hwy::HWY_NAMESPACE::MaskedNe(mask, a,b);
        }

        template<typename T, int N, int K, 
                 typename M = hwy::HWY_NAMESPACE::MFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE M Not(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/, const M & mask)
        {
            return  hwy::HWY_NAMESPACE::Not(mask);
        }

        template<typename T, int SN, int SK, int DN, int DK, 
                 typename SV = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,SN,SK>>,
                 typename DV = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,DN,DK>>>
        static HWY_ATTR HWY_INLINE DV ResizeBitCast(const hwy::HWY_NAMESPACE::Simd<T,SN,SK> & srcd, 
                                                   const hwy::HWY_NAMESPACE::Simd<T,DN,DK> & /*destd*/, 
                                                   const SV & v)
        {
            const hwy::HWY_NAMESPACE::Simd<T, DN, DK> _dst;
            return  hwy::HWY_NAMESPACE::ResizeBitCast(_dst, v);
        }

        
        template<typename T, int N, int K, 
                 typename V = hwy::HWY_NAMESPACE::VFromD<hwy::HWY_NAMESPACE::Simd<T,N,K>>>
        static HWY_ATTR HWY_INLINE V Sub(const hwy::HWY_NAMESPACE::Simd<T,N,K> & /*d*/, const V & a, const V & b)
        {
            return  hwy::HWY_NAMESPACE::Sub(a,b);
        }

    }
}