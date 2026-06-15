#pragma once

#include <map>

namespace Debug
{
    class Logger
    {
    public:
     

        inline Logger()
        {}

        inline void LogValue(size_t x, const char * caption, float value)
        {
            const auto & found = buf_.find(x);
            if(found != buf_.end())
            {
                auto & foundentry = (*((*found).second))[caption];
                foundentry.push_back(value);
            }
            else
            {
                std::shared_ptr<std::map<std::string, std::vector<float>>> newentryptr = std::make_shared<std::map<std::string, std::vector<float>>>();
                buf_[x] = newentryptr;
                auto & newentry = (*newentryptr)[caption];
                newentry.push_back(value);
            }

            if(x > lastValue_)
                lastValue_ = x;
        }

        inline std::shared_ptr<std::map<std::string, std::vector<float>>>  GetBuffer(size_t x) const
        {
            const auto & found = buf_.find(x);
            if(found != buf_.end())
            {
                return (*found).second;
            }

            return std::shared_ptr<std::map<std::string, std::vector<float>>>();
        }

        /*inline const char * GetString(size_t x, std::string & out) const
        {
            std::stringstream strm;
            const auto & found = buf_.find(x);
            if(found != buf_.end())
            {
                bool firstline = true;
                for(const auto & itr : *((*found).second))
                {
                    if(!firstline)
                        strm << "\n";

                    strm << itr.caption << " (" << itr.data.size() << ") : ";
                    bool first = true;
                    for(const auto & fltitr : itr.data)
                    {
                        if(!first)
                            strm << ", ";

                        strm << std::setprecision(10) << std::fixed << fltitr;
                        first = false;
                    }

                    firstline = false;
                }
            }
            else
            {
                out = "";
            }

            out = strm.str();
            return out.c_str();
        }*/

        inline size_t GetSize() const
        {
            if(buf_.size() == 0)
                return 0;

            return lastValue_ + 1;
        }

    private:
        
        std::map<size_t, std::shared_ptr<std::map<std::string, std::vector<float>>>> buf_;
        size_t lastValue_ = 0;
    };

}