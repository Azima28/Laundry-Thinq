import sys
import webview
import urllib.parse

def main():
    if len(sys.argv) < 2:
        print("ERROR: Missing login URL parameter", file=sys.stderr)
        sys.exit(1)
        
    login_url = sys.argv[1]
    
    # We will print the final redirect URL to stdout once captured
    captured_url = None

    def on_loaded(*args, **kwargs):
        nonlocal captured_url
        url = window.get_current_url()
        if url and "code=" in url and ("iabClose" in url or "lgaccount.lgsmartthinq" in url or "kr.m.lgaccount.com" in url):
            captured_url = url
            # Close the window
            window.destroy()

    window = webview.create_window(
        title='Login LG ThinQ',
        url=login_url,
        width=500,
        height=680,
        resizable=True
    )
    
    # Register loaded event listener
    window.events.loaded += on_loaded

    # Start the webview GUI loop
    webview.start()
    
    if captured_url:
        print(f"CALLBACK_URL:{captured_url}")
        sys.exit(0)
    else:
        print("ERROR: Window closed by user without login", file=sys.stderr)
        sys.exit(2)

if __name__ == '__main__':
    main()
