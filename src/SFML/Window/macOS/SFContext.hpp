////////////////////////////////////////////////////////////
//
// SFML - Simple and Fast Multimedia Library
// Copyright (C) 2007-2026 Marco Antognini (antognini.marco@gmail.com),
//                         Laurent Gomila (laurent@sfml-dev.org)
//
// This software is provided 'as-is', without any express or implied warranty.
// In no event will the authors be held liable for any damages arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it freely,
// subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented;
//    you must not claim that you wrote the original software.
//    If you use this software in a product, an acknowledgment
//    in the product documentation would be appreciated but is not required.
//
// 2. Altered source versions must be plainly marked as such,
//    and must not be misrepresented as being the original software.
//
// 3. This notice may not be removed or altered from any source distribution.
//
////////////////////////////////////////////////////////////

#pragma once

////////////////////////////////////////////////////////////
// Headers
////////////////////////////////////////////////////////////
#include <SFML/Window/GlContext.hpp>

////////////////////////////////////////////////////////////
/// Predefine OBJC classes
////////////////////////////////////////////////////////////
#ifdef __OBJC__

@class NSView;
using NSViewRef = NSView*;

@class NSWindow;
using NSWindowRef = NSWindow*;

#else // If C++

using NSViewRef   = void*;
using NSWindowRef = void*;

#endif


namespace sf::priv
{
////////////////////////////////////////////////////////////
class SFContext : public GlContext
{
public:
    ////////////////////////////////////////////////////////////
    SFContext(SFContext* shared);

    ////////////////////////////////////////////////////////////
    SFContext(SFContext* shared, const ContextSettings& settings, const WindowImpl& owner, unsigned int bitsPerPixel);

    ////////////////////////////////////////////////////////////
    SFContext(SFContext* shared, const ContextSettings& settings, Vector2u size);

    ////////////////////////////////////////////////////////////
    ~SFContext() override;

    ////////////////////////////////////////////////////////////
    static GlFunctionPointer getFunction(const char* name);

    ////////////////////////////////////////////////////////////
    void display() override;

    ////////////////////////////////////////////////////////////
    void setVerticalSyncEnabled(bool enabled) override;

protected:
    ////////////////////////////////////////////////////////////
    bool makeCurrent(bool current) override;

private:
    ////////////////////////////////////////////////////////////
    void createContext(SFContext* shared, const ContextSettings& settings, NSViewRef view);

    ////////////////////////////////////////////////////////////
    // Member data
    ////////////////////////////////////////////////////////////
    void*       m_context{};  ///< MooGL context.
    void*       m_renderer{}; ///< Its MGLRenderer, retained.
    NSViewRef   m_view{};     ///< Only for offscreen context.
    NSWindowRef m_window{};   ///< Only for offscreen context.
};

} // namespace sf::priv
