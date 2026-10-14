// A vector that several threads may push to (Instant Meshes' collapse candidates); read once the pushing is over.
#pragma once

#include <mutex>
#include <vector>

#include "tbb.h"

namespace tbb {

template <typename T> class concurrent_vector {
public:
    void reserve(size_t count) { mItems.reserve(count); }
    void push_back(const T &value) {
        std::lock_guard<std::mutex> guard(mMutex);
        mItems.push_back(value);
    }
    size_t size() const { return mItems.size(); }
    T &operator[](size_t index) { return mItems[index]; }
    const T &operator[](size_t index) const { return mItems[index]; }
    typename std::vector<T>::iterator begin() { return mItems.begin(); }
    typename std::vector<T>::iterator end() { return mItems.end(); }

private:
    std::mutex mMutex;
    std::vector<T> mItems;
};

}
