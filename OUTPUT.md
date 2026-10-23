Fixed mobile Safari annotation UX:
- Suppress the document selection callout using -webkit-touch-callout and contextmenu cancellation, retain text selection, and capture selections promptly on touchend.
- Clamp annotation UI to visualViewport bounds with 12px padding, constrain popover size, reposition on keyboard viewport resize/scroll, and scroll/reposition after focusing new, existing, or restored comments.
- Use layout-coordinate DOM rects against the offset visible viewport box, avoiding double-applied offsets.
Validation: all 37 unit tests pass; TypeScript check and Vite production build pass. Updated local web/dist. No running local Loop Web service was detected to restart; no installed native app was changed for this web-only fix.
Remaining verification: real-device Safari keyboard behavior. Some iOS versions may still briefly display the native selection menu.
Local commit only; no push.
