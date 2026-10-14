// Instant Meshes' save and load of its interactive state; Maquette never saves it, so it does nothing.
#pragma once

#include <string>

class Serializer {
public:
    template <typename T> void set(const std::string &, const T &) {}
    template <typename T> bool get(const std::string &, T &) const { return false; }
    void pushPrefix(const std::string &) const {}
    void popPrefix() const {}
};
