
#include <hwy/print-inl.h>
#include <hwy/print.h>


#ifndef ENABLE_LOGGING
    #ifdef _DEBUG
        #define ENABLE_LOGGING
    #endif
#endif

#ifndef DEBUG_LOG_VALUE
    #ifdef ENABLE_LOGGING
        #define DEBUG_LOG_VALUE(LOG, NUM, TXT, VAL)  (LOG).LogValue(NUM, TXT, VAL);
    #else
        #define DEBUG_LOG_VALUE(LOG, NUM, TXT, VAL)
    #endif
#endif

#ifndef DEBUG_LOG_VALUE_EX
    #ifdef ENABLE_LOGGING
        #define DEBUG_LOG_VALUE_EX(LOG, NUM, TXT, VAL)  do { std::ostringstream __txt; __txt << TXT;   (LOG).LogValue(NUM, __txt.str().c_str(), VAL); } while(0)
    #else
        #define DEBUG_LOG_VALUE_EX(LOG, NUM, TXT, VAL)
    #endif
#endif

#ifndef DEBUG_LOG_LANES
    #ifdef ENABLE_LOGGING
        #define DEBUG_LOG_LANES(LOG, NUM, TXT, VAL)   hwy::HWY_NAMESPACE::Debug::OutputLanes(LOG, NUM, TXT, VAL);
    #else
        #define DEBUG_LOG_LANES(LOG, NUM, TXT, VAL)
    #endif
#endif

#ifndef DEBUG_LOG_LANES_EX
    #ifdef ENABLE_LOGGING
        #define DEBUG_LOG_LANES_EX(LOG, NUM, TXT, VAL)   do { std::ostringstream __txt; __txt << TXT; hwy::HWY_NAMESPACE::Debug::OutputLanes(LOG, NUM,  __txt.str().c_str(), VAL); } while(0)
    #else
        #define DEBUG_LOG_LANES_EX(LOG, NUM, TXT, VAL)
    #endif
#endif

#ifndef DEBUG_LOG_LANES_MASK
    #ifdef ENABLE_LOGGING
        #define DEBUG_LOG_LANES_MASK(LOG, NUM, TXT, VAL, MSK)   hwy::HWY_NAMESPACE::Debug::OutputLanesMask(LOG, NUM, TXT, VAL, MSK);
    #else
        #define DEBUG_LOG_LANES_MASK(LOG, NUM, TXT, VAL, MSK)
    #endif
#endif

#ifndef DEBUG_LOG_LANES_MASK_EX
    #ifdef ENABLE_LOGGING
        #define DEBUG_LOG_LANES_MASK_EX(LOG, NUM, TXT, VAL, MSK)   do { std::ostringstream __txt; __txt << TXT; hwy::HWY_NAMESPACE::Debug::OutputLanesMask(LOG, NUM, __txt.str().c_str(), VAL, MSK); } while(0)
    #else
        #define DEBUG_LOG_LANES_MASK_EX(LOG, NUM, TXT, VAL, MSK)
    #endif
#endif

HWY_BEFORE_NAMESPACE();
namespace hwy
{
    namespace HWY_NAMESPACE
    {
        struct Debug
        {
            template<class L, typename H>
            static HWY_INLINE void OutputLanes(L & log, size_t x, const char * caption, const H & val)
            {
                const hwy::HWY_NAMESPACE::DFromV<H> _type;
                const size_t numLanes = hwy::HWY_NAMESPACE::Lanes(_type);

                HWY_ALIGN hwy::HWY_NAMESPACE::TFromV<H> lanes[_type.MaxLanes()];

                hwy::HWY_NAMESPACE::Store(val, _type, lanes);

                for(size_t i = 0; i < numLanes; ++i)
                {
                    log.LogValue(x + i, caption, static_cast<float>( lanes[i]));
                }
            }

            template<class L, typename H, typename M>
            static HWY_INLINE void OutputLanesMask(L & log, size_t x, const char * caption, const H & val, const M & mask)
            {
                const hwy::HWY_NAMESPACE::DFromV<H> _type;
                const size_t numLanes = hwy::HWY_NAMESPACE::Lanes(_type);

                HWY_ALIGN hwy::HWY_NAMESPACE::TFromV<H> lanes[_type.MaxLanes()];
                HWY_ALIGN uint8_t maskbytes[_type.MaxLanes()];

                hwy::HWY_NAMESPACE::Store(val, _type, lanes);
                hwy::HWY_NAMESPACE::StoreMaskBits(_type, mask, maskbytes);
                size_t maskoffset = 0;
                size_t curmask = maskbytes[0];
                size_t maskshift = 0;
                for(size_t i = 0; i < numLanes; ++i)
                {
                    if(maskshift == 8)
                    {
                        maskshift=0;
                        ++maskoffset;
                        curmask = maskbytes[maskoffset];
                    }

                    if((curmask >> maskshift) & 1)
                        log.LogValue(x + i, caption, static_cast<float>(lanes[i]));

                    ++maskshift;
                }
            }
        };
    }
}
HWY_AFTER_NAMESPACE();
