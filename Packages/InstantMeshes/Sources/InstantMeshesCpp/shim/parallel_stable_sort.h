// pss::parallel_stable_sort, as a stable sort on the calling thread (the same order, deterministically).
#pragma once

#include <algorithm>

namespace pss {

template <typename Iterator, typename Compare> void parallel_stable_sort(Iterator begin, Iterator end, Compare compare) {
    std::stable_sort(begin, end, compare);
}

}
