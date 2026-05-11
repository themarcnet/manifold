
#if HWY_ONCE || HWY_IDE
namespace hwy
{
    enum RunHighwayErrorCode
    {
        RunHighwayErrorCode_Success = 0,
        RunHighwayErrorCode_Target_Out_Of_Range = 1,
        RunHighwayErrorCode_Target_Not_Implemented = 2,
        RunHighwayErrorCode_Target_Not_Supported = 3,
        RunHighwayErrorCode_Error = 4
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
