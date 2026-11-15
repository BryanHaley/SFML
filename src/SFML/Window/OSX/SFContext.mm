////////////////////////////////////////////////////////////
//
// SFML - Simple and Fast Multimedia Library
// Copyright (C) 2007-2023 Marco Antognini (antognini.marco@gmail.com),
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

////////////////////////////////////////////////////////////
// Headers
////////////////////////////////////////////////////////////
#include <SFML/Window/OSX/AutoreleasePoolWrapper.hpp>
#include <SFML/Window/OSX/SFContext.hpp>
#include <SFML/Window/OSX/WindowImplCocoa.hpp>
#include <SFML/System/Err.hpp>
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <stdint.h>

// MooGL: OpenGL 4.6 on Metal in place of Apple's NSOpenGL. Modified from
// SFML's NSOpenGL version for MooGL.

// From libmoogl. MGLRenderer.h needs Metal's headers, so the few calls used
// here are declared instead.
extern "C"
{
typedef struct GLMContextRec_t* GLMContext;
GLMContext createGLMContext(unsigned format, unsigned type, unsigned depthFormat, unsigned depthType,
                            unsigned stencilFormat, unsigned stencilType);
GLMContext createGLMContextProfile(unsigned format, unsigned type, unsigned depthFormat, unsigned depthType,
                                   unsigned stencilFormat, unsigned stencilType, GLMContext share, unsigned profile);
void destroyGLMContext(GLMContext ctx);
GLMContext MGLgetCurrentContext(void);
void MGLsetCurrentContext(GLMContext ctx);
void MGLswapBuffers(GLMContext ctx);
void MGLsetSwapInterval(GLMContext ctx, int interval);
void MGLsetContextFlags(GLMContext ctx, unsigned flags);
void* CppCreateMGLRendererHeadless(void* ctx);
}

@interface MGLRenderer : NSObject
-(void)createMGLRendererAndBindToContext:(GLMContext)glmCtx view:(NSView*)view;
@end

namespace
{
const unsigned mglBgra             = 0x80E1;
const unsigned mglUnsignedInt8888  = 0x8367;
const unsigned mglDepthComponent   = 0x1902;
const unsigned mglFloat            = 0x1406;
const unsigned mglStencilIndex8    = 0x8D48;
const unsigned mglUnsignedByte     = 0x1401;
const unsigned mglCoreProfile      = 0x1;
const unsigned mglCompatProfile    = 0x2;
const unsigned mglContextFlagDebug = 0x2;

// MooGL has to have a context current for the GL entry points to land
// anywhere, so this stands in when SFML has none
GLMContext placeholderContext()
{
    static GLMContext placeholder = createGLMContext(0, 0, 0, 0, 0, 0);
    return placeholder;
}
}

namespace sf
{
namespace priv
{


////////////////////////////////////////////////////////////
SFContext::SFContext(SFContext* shared) :
m_context(0),
m_renderer(0),
m_view(0),
m_window(0)
{
    AutoreleasePool pool;
    createContext(shared, ContextSettings(0, 0, 0), nil);
}


////////////////////////////////////////////////////////////
SFContext::SFContext(SFContext* shared, const ContextSettings& settings,
                     const WindowImpl* owner, unsigned int /* bitsPerPixel */) :
m_context(0),
m_renderer(0),
m_view(0),
m_window(0)
{
    AutoreleasePool pool;
    const WindowImplCocoa* ownerCocoa = static_cast<const WindowImplCocoa*>(owner);
    createContext(shared, settings, ownerCocoa->getContextView());
}


////////////////////////////////////////////////////////////
SFContext::SFContext(SFContext* shared, const ContextSettings& settings,
                     unsigned int width, unsigned int height) :
m_context(0),
m_renderer(0),
m_view(0),
m_window(0)
{
    AutoreleasePool pool;
    // Ensure the process is setup in order to create a valid window.
    WindowImplCocoa::setUpProcess();

    // A hidden window and view to draw into.
    m_window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
                                           styleMask:NSWindowStyleMaskBorderless
                                             backing:NSBackingStoreBuffered
                                               defer:NO]; // Don't defer it!
    m_view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
    [m_window setContentView:m_view];

    createContext(shared, settings, m_view);
}


////////////////////////////////////////////////////////////
SFContext::~SFContext()
{
    AutoreleasePool pool;
    // Notify unshared OpenGL resources of context destruction
    cleanupUnsharedResources();

    if (m_context)
    {
        if (MGLgetCurrentContext() == m_context)
            MGLsetCurrentContext(placeholderContext());
        destroyGLMContext(static_cast<GLMContext>(m_context));
    }

    if (m_renderer)
        CFRelease(m_renderer);

    [m_view release]; // Might be nil but we don't care.
    [m_window release]; // Idem.
}


////////////////////////////////////////////////////////////
GlFunctionPointer SFContext::getFunction(const char* name)
{
    static void* image = NULL;

    // always the copy of libmoogl SFML is linked against; a second copy would
    // have its own current context
    if (!image)
    {
        Dl_info info;
        if (dladdr(reinterpret_cast<const void*>(createGLMContext), &info) && info.dli_fname)
            image = dlopen(info.dli_fname, RTLD_LAZY | RTLD_LOCAL);
    }

    return (image ? reinterpret_cast<GlFunctionPointer>(reinterpret_cast<intptr_t>(dlsym(image, name))) : 0);
}


////////////////////////////////////////////////////////////
bool SFContext::makeCurrent(bool current)
{
    if (!m_context)
        return false;

    MGLsetCurrentContext(current ? static_cast<GLMContext>(m_context) : placeholderContext());
    return true;
}


////////////////////////////////////////////////////////////
void SFContext::display()
{
    AutoreleasePool pool;
    MGLswapBuffers(static_cast<GLMContext>(m_context));
}


////////////////////////////////////////////////////////////
void SFContext::setVerticalSyncEnabled(bool enabled)
{
    MGLsetSwapInterval(static_cast<GLMContext>(m_context), enabled ? 1 : 0);
}


////////////////////////////////////////////////////////////
void SFContext::createContext(SFContext* shared,
                              const ContextSettings& settings,
                              NSViewRef view)
{
    AutoreleasePool pool;
    // Save the settings. (OpenGL version is updated elsewhere.)
    m_settings = settings;

    // Every version up to 4.6 gets 4.6; a core context only when asked for one
    const bool core = m_settings.majorVersion >= 3 && (m_settings.attributeFlags & ContextSettings::Core);
    const bool depth = m_settings.depthBits > 0;
    const bool stencil = m_settings.stencilBits > 0;

    // MooGL's default framebuffer has no multisampling
    m_settings.antialiasingLevel = 0;
    m_settings.sRgbCapable = false;

    m_context = createGLMContextProfile(mglBgra, mglUnsignedInt8888,
                                        depth ? mglDepthComponent : 0, depth ? mglFloat : 0,
                                        stencil ? mglStencilIndex8 : 0, stencil ? mglUnsignedByte : 0,
                                        shared ? static_cast<GLMContext>(shared->m_context) : NULL,
                                        core ? mglCoreProfile : mglCompatProfile);
    if (!m_context)
    {
        err() << "Error. Unable to create the context." << std::endl;
        return;
    }

    if (m_settings.attributeFlags & ContextSettings::Debug)
        MGLsetContextFlags(static_cast<GLMContext>(m_context), mglContextFlagDebug);

    GLMContext was = MGLgetCurrentContext();
    MGLsetCurrentContext(static_cast<GLMContext>(m_context));
    if (view != nil)
    {
        MGLRenderer* renderer = [[MGLRenderer alloc] init];
        [renderer createMGLRendererAndBindToContext:static_cast<GLMContext>(m_context) view:view];
        m_renderer = const_cast<void*>(CFBridgingRetain(renderer));
        [renderer release];
    }
    else
    {
        m_renderer = CppCreateMGLRendererHeadless(m_context);
        CFRetain(m_renderer);
    }
    MGLsetCurrentContext(was ? was : placeholderContext());
}

} // namespace priv

} // namespace sf
