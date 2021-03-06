// Copyright (c) 2022 David Gallardo and SDFEditor Project

#include <sbx/Core/ErrorHandling.h>

#if SBX_ERRORS_ENABLED
#include <stdarg.h>
#include <stdio.h>

namespace __sbx_assert
{
    bool EvalAssert(bool const & aTest, char* aTestStr, char* aFile, int32_t aLine, char* aFormat, ...)
    {
        if(!aTest)
        { 
            va_list  lArgsList;
            va_start(lArgsList, aFormat);
            ::vsnprintf(__sbx_assert::GetAssertBuff<1024>(), 1024, aFormat, lArgsList);
            va_end(lArgsList);
            SBX_LOG("[Assert in %s:%d] (%s) - %s", aFile, aLine, aTestStr, __sbx_assert::GetAssertBuff<1024>()); 

            return true; //TODO: os modal to ask if stop, no stop, ignore rest
        }

        return false;
    }
}

#endif