#pragma once

#include <map>
#include <vector>
#include <memory>
#include <iomanip>
#include <cmath>

namespace Debug
{
    class Logger
    {
    public:
        inline void SetLogStartValues(size_t x)
        {
            logStart_ = x;
        }
        
        inline void LogValue(size_t x, const char * caption, float value)
        {
            if(x < logStart_)
                return;

            bool first = buf_.size() == 0;

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

            if(first || (x < firstValue_))
                firstValue_ = x;
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

        inline size_t GetSize() const
        {
            if(buf_.size() == 0)
                return 0;

            return lastValue_ + 1;
        }

        inline void Clear()
        {
            lastValue_ = 0;
            firstValue_ = 0;
            buf_.clear();
        }

        static void CompareLogsToStream(std::ostream & strm,  
                                        const char * log1name, const Logger & log1, 
                                        const char * log2name, const Logger & log2)
        {   
            char valdump[256];
            const size_t first = log1.firstValue_ < log2.firstValue_ ? log1.firstValue_ : log2.firstValue_;
            const size_t last = log1.lastValue_ > log2.lastValue_ ? log1.lastValue_ : log2.lastValue_;

            //Check if there is anything to log
            if((first < log1.logStart_) && (last < log1.logStart_) && (first < log2.logStart_) && (last < log2.logStart_))
                return;

            if(log1name == NULL)
                log1name = "LOG 1";

            if(log2name == NULL)
                log2name = "LOG 2";

            for(size_t x = first; x <= last; ++x)
            {
                std::shared_ptr<std::map<std::string, std::vector<float>>> log1_entry, log2_entry;

                strm << "------------------------";
                if(x == first)
                    strm << "--- Page Break ---";
                
                strm << "------------------";
                
                strm << "\n" << x << ")\n";

                log1_entry = log1.GetBuffer(x);
                log2_entry = log2.GetBuffer(x);
                if(log1_entry.get() != NULL)
                {
                    for(const auto & entry : (*log1_entry))
                    {
                        strm << "\t" << entry.first << " : " << log1name << ": ";
                        bool firstdata = true;
                        for(const auto & data : entry.second)
                        {
                            if(!firstdata)
                                strm << ", ";

                            snprintf(valdump, sizeof(valdump) - 1, "%a", data);
                            strm << std::setprecision(10) << std::fixed << data << " (" << valdump << ")";
                            firstdata = false;
                        }

                        strm << "\t\t";
                        bool havediff = false;
                        float maxDiff = 0;
                        if(log2_entry == NULL)
                        {
                            strm << " " << log2name << ": <NO ENTRY>";
                        }
                        else
                        {
                            const auto & found2entry = (*log2_entry).find(entry.first);
                            if(found2entry != (*log2_entry).end())
                            {
                                havediff = entry.second != (*found2entry).second;

                                strm << " " << log2name << ": ";
                                firstdata = true;
                                auto cmp = entry.second.begin();
                                for(const auto & data : (*found2entry).second)
                                {
                                    if(!firstdata)
                                        strm << ", ";

                                    if(havediff && (cmp != entry.second.end()))
                                    {
                                        float d = std::fabs(data - (*cmp));
                                        if(d > maxDiff)
                                            maxDiff = d;

                                        ++cmp;
                                    }

                                    snprintf(valdump, sizeof(valdump) - 1, "%a", data);
                                    strm << std::setprecision(10) << std::fixed << data << " (" << valdump << ")";
                                    firstdata = false;
                                }

                                if(havediff)
                                {
                                    strm << " : DIFFERENCE !!!! - MaxDiff" << std::setprecision(10) << std::fixed << maxDiff;
                                }
                            }
                            else
                            {
                                strm << " " << log2name << ": <NOT FOUND>";
                            }
                        }

                        strm << "\n";
                    }
                }

                if(log2_entry != NULL)
                {
                    for(const auto & entry : (*log2_entry))
                    {
                        if(log1_entry == NULL)
                        {
                            bool firstdata = true;
                            strm << "\t" << entry.first << " : " << log1name << ": <NO ENTRY> \t\t\t\t\t " << log2name << ": ";
                            for(const auto & data : entry.second)
                            {
                                if(!firstdata)
                                    strm << ", ";

                                snprintf(valdump, sizeof(valdump) - 1, "%a", data);
                                strm << std::setprecision(10) << std::fixed << data << " (" << valdump << ")";
                                firstdata = false;
                            }

                            strm << "\n";
                        }
                        else
                        {
                            const auto & foundlog1 = (*log1_entry).find(entry.first);
                            if(foundlog1 == (*log1_entry).end())
                            {
                                bool firstdata = true;
                                strm << "\t" << entry.first << " : " << log1name << " : <NOT FOUND> \t\t\t\t\t " << log2name << ": ";
                                for(const auto & data : entry.second)
                                {
                                    if(!firstdata)
                                        strm << ", ";

                                    snprintf(valdump, sizeof(valdump) - 1, "%a", data);
                                    strm << std::setprecision(10) << std::fixed << data << " (" << valdump << ")";
                                    firstdata = false;
                                }

                                strm << "\n";
                            }
                        }
                    }

                    strm << "\n\n";
                }
            }

            strm.flush();
        }

    private:
        
        std::map<size_t, std::shared_ptr<std::map<std::string, std::vector<float>>>> buf_;
        size_t lastValue_ = 0;
        size_t firstValue_ = 0;
        size_t logStart_ = 0;
    };

}
