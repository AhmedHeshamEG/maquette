// The small part of Threading Building Blocks that Instant Meshes uses, on the standard library. Loops run in a few
// threads (each body is written to be run in parallel: the field is coloured into independent phases, shared state
// takes a spin mutex); reductions, sorts and the tree build run on the calling thread.
#pragma once

#include <algorithm>
#include <atomic>
#include <cstddef>
#include <functional>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

namespace tbb {

template <typename T> class blocked_range {
public:
    blocked_range() = default;
    blocked_range(T begin, T end, size_t grain = 1) : mBegin(begin), mEnd(end), mGrain(grain ? grain : 1) {}
    T begin() const { return mBegin; }
    T end() const { return mEnd; }
    size_t size() const { return size_t(mEnd - mBegin); }
    size_t grainsize() const { return mGrain; }
    bool empty() const { return !(mBegin < mEnd); }

private:
    T mBegin {};
    T mEnd {};
    size_t mGrain = 1;
};

namespace detail {
    inline unsigned threads() {
        unsigned count = std::thread::hardware_concurrency();
        return count == 0 ? 1 : std::min(count, 8u);
    }

    // Runs body(chunk) for chunks of [begin, end) on up to threads() threads; chunks are at least `grain` long.
    template <typename T, typename Body> void fan_out(T begin, T end, size_t grain, const Body &body) {
        if (!(begin < end)) return;
        size_t total = size_t(end - begin);
        size_t workers = std::min<size_t>(threads(), std::max<size_t>(1, total / std::max<size_t>(grain, 1)));
        if (workers <= 1) {
            body(blocked_range<T>(begin, end, grain));
            return;
        }
        size_t chunk = std::max<size_t>(grain, 1);
        std::atomic<size_t> next {0};
        auto work = [&]() {
            for (;;) {
                size_t start = next.fetch_add(chunk);
                if (start >= total) break;
                size_t stop = std::min(total, start + chunk);
                body(blocked_range<T>(T(begin + start), T(begin + stop), grain));
            }
        };
        std::vector<std::thread> pool;
        pool.reserve(workers - 1);
        for (size_t i = 1; i < workers; ++i) pool.emplace_back(work);
        work();
        for (auto &thread : pool) thread.join();
    }
}

template <typename T, typename Body> void parallel_for(const blocked_range<T> &range, const Body &body) {
    detail::fan_out(range.begin(), range.end(), range.grainsize(), body);
}

template <typename T, typename Func> void parallel_for(T begin, T end, const Func &func) {
    detail::fan_out(begin, end, 1024, [&](const blocked_range<T> &range) {
        for (T i = range.begin(); i != range.end(); ++i) func(i);
    });
}

// Functional form: map over chunks in order, join left to right (deterministic).
template <typename T, typename Value, typename Map, typename Reduce>
Value parallel_reduce(const blocked_range<T> &range, const Value &identity, const Map &map, const Reduce &reduce) {
    Value result = identity;
    size_t grain = std::max<size_t>(range.grainsize(), 1);
    for (T start = range.begin(); start < range.end();) {
        T stop = T(std::min<size_t>(size_t(range.end() - range.begin()), size_t(start - range.begin()) + grain) + range.begin());
        result = reduce(result, map(blocked_range<T>(start, stop, grain), identity));
        start = stop;
    }
    return result;
}

template <typename T, typename Value, typename Map, typename Reduce>
Value parallel_deterministic_reduce(const blocked_range<T> &range, const Value &identity, const Map &map, const Reduce &reduce) {
    return parallel_reduce(range, identity, map, reduce);
}

template <typename Iterator, typename Compare> void parallel_sort(Iterator begin, Iterator end, const Compare &compare) {
    std::sort(begin, end, compare);
}

class spin_mutex {
public:
    void lock() {
        while (mFlag.test_and_set(std::memory_order_acquire)) std::this_thread::yield();
    }
    void unlock() { mFlag.clear(std::memory_order_release); }

    class scoped_lock {
    public:
        scoped_lock() = default;
        explicit scoped_lock(spin_mutex &mutex) : mMutex(&mutex) { mutex.lock(); }
        ~scoped_lock() { release(); }
        void acquire(spin_mutex &mutex) {
            release();
            mMutex = &mutex;
            mutex.lock();
        }
        void release() {
            if (mMutex) mMutex->unlock();
            mMutex = nullptr;
        }
        scoped_lock(const scoped_lock &) = delete;
        scoped_lock &operator=(const scoped_lock &) = delete;

    private:
        spin_mutex *mMutex = nullptr;
    };

    spin_mutex() = default;
    spin_mutex(const spin_mutex &) {}
    spin_mutex &operator=(const spin_mutex &) { return *this; }

private:
    std::atomic_flag mFlag = ATOMIC_FLAG_INIT;
};

template <typename T, typename Compare = std::less<T>> class concurrent_priority_queue {
public:
    void push(const T &value) {
        std::lock_guard<std::mutex> guard(mMutex);
        mQueue.push(value);
    }
    bool try_pop(T &value) {
        std::lock_guard<std::mutex> guard(mMutex);
        if (mQueue.empty()) return false;
        value = mQueue.top();
        mQueue.pop();
        return true;
    }
    bool empty() const {
        std::lock_guard<std::mutex> guard(mMutex);
        return mQueue.empty();
    }
    size_t size() const {
        std::lock_guard<std::mutex> guard(mMutex);
        return mQueue.size();
    }

private:
    mutable std::mutex mMutex;
    std::priority_queue<T, std::vector<T>, Compare> mQueue;
};

// A task tree run on one thread: spawn runs a child to completion; execute() returning a task continues with it.
class task {
public:
    virtual ~task() = default;
    virtual task *execute() = 0;

    static void run(task *start) {
        for (task *current = start; current;) {
            task *next = current->execute();
            if (next != current) delete current;
            current = next;
        }
    }

    struct allocation {};
    static allocation allocate_root() { return {}; }
    allocation allocate_continuation() { return {}; }
    allocation allocate_child() { return {}; }
    void set_ref_count(int) {}
    void recycle_as_child_of(task &) {}
    static void spawn(task &child) { run(&child); }
    static void spawn_root_and_wait(task &root) { run(&root); }
};

// The optimiser asks for a thread count; the loops above choose their own.
class task_scheduler_init {
public:
    static const int automatic = -1;
    explicit task_scheduler_init(int = automatic) {}
};

class empty_task : public task {
public:
    task *execute() override { return nullptr; }
};

}

inline void *operator new(size_t size, tbb::task::allocation) { return ::operator new(size); }
