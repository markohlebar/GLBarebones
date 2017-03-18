//
//  GLView.swift
//  TrailerMaker
//
//  Created by Marko Hlebar on 18/03/2017.
//  Copyright © 2017 Marko Hlebar. All rights reserved.
//

import Cocoa
import GLKit

func displayLinkCallback(displayLink: CVDisplayLink,
                         now: UnsafePointer<CVTimeStamp>,
                         outputTime: UnsafePointer<CVTimeStamp>,
                         flagsIn: CVOptionFlags,
                         flagsOut: UnsafeMutablePointer<CVOptionFlags>,
                         context: UnsafeMutableRawPointer?) -> CVReturn {
    guard let context = context else { return 0 }

    let glView = Unmanaged<GLView>.fromOpaque(context).takeUnretainedValue()
    glView.drawView()

    return 1
}

class GLView: NSOpenGLView {

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawView()
    }

    var displayLink: CVDisplayLink?

    lazy var pixelFormatAttributes: [NSOpenGLPixelFormatAttribute] = {
        return [
            NSOpenGLPFADoubleBuffer,
            NSOpenGLPFADepthSize, 24,
            NSOpenGLPFAOpenGLProfile,
            NSOpenGLProfileVersion3_2Core,
            0].map {
                NSOpenGLPixelFormatAttribute($0)
        }
    }()

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func awakeFromNib() {
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: pixelFormatAttributes) else { return }
        self.pixelFormat = pixelFormat

        guard let context = NSOpenGLContext(format: pixelFormat, share: nil) else { return }
        self.openGLContext = context

        // Support retina display
        self.wantsBestResolutionOpenGLSurface = true

        // When we're using a CoreProfile context, crash if we call a legacy OpenGL function
        // This will make it much more obvious where and when such a function call is made so
        // that we can remove such calls.
        // Without this we'd simply get GL_INVALID_OPERATION error for calling legacy functions
        // but it would be more difficult to see where that function was called.
        if let object = context.cglContextObj {
            CGLEnable(object, kCGLCECrashOnRemovedFunctions)
        }
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()

        initGL()
        initDisplayLink()
    }

    func initDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let displayLink = displayLink else { return }
        CVDisplayLinkSetOutputCallback(displayLink, displayLinkCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        if let context = openGLContext?.cglContextObj, let pixelFormat = pixelFormat?.cglPixelFormatObj {
            CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(displayLink, context, pixelFormat)
        }

        CVDisplayLinkStart(displayLink)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(windowWillClose),
                                               name: Notification.Name.NSWindowWillClose,
                                               object: nil)
    }

    func windowWillClose(_ notification: NSNotification) {
        guard let displayLink = displayLink else { return }
        CVDisplayLinkStop(displayLink)
    }

    func initGL() {
        guard let context = openGLContext else { return }

        // The reshape function may have changed the thread to which our OpenGL
        // context is attached before prepareOpenGL and initGL are called.  So call
        // makeCurrentContext to ensure that our OpenGL context current to this
        // thread (i.e. makeCurrentContext directs all OpenGL calls on this thread
        // to [self openGLContext])
        context.makeCurrentContext()

        // Synchronize buffer swaps with vertical refresh rate
        var swapInt: GLint = 1
        context.setValues(&swapInt, for: NSOpenGLCPSwapInterval)
    }

    func drawView() {
        guard let context = openGLContext, let cglContext = context.cglContextObj else { return }
        context.makeCurrentContext()

        // We draw on a secondary thread through the display link
        // When resizing the view, -reshape is called automatically on the main
        // thread. Add a mutex around to avoid the threads accessing the context
        // simultaneously when resizing
        CGLLockContext(cglContext);

        glClearColor(1.0, 0.0, 0.0, 1.0);
        glClear(UInt32(GL_COLOR_BUFFER_BIT));

        CGLFlushDrawable(cglContext);
        CGLUnlockContext(cglContext);
    }
}
