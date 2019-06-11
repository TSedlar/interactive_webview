import Flutter
import WebKit
import UIKit

enum CallMethod: String {
    case setOptions = "setOptions"
    case evalJavascript = "evalJavascript"
    case loadHTML = "loadHTML"
    case loadUrl = "loadUrl"
}

public class SwiftInteractiveWebviewPlugin: NSObject, FlutterPlugin {
  
    private let configuration: WKWebViewConfiguration = WKWebViewConfiguration()
    private let webView: WKWebView
    
    private let channel: FlutterMethodChannel
    
    private var restrictedSchemes = [String]()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "interactive_webview", binaryMessenger: registrar.messenger())
        let instance = SwiftInteractiveWebviewPlugin(withChannel: channel)
        
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let method = CallMethod(rawValue: call.method) else { return }
        
        switch method {
        case .setOptions: setupOptions(call)
        case .evalJavascript: evalJavascript(call)
        case .loadHTML: loadHTML(call)
        case .loadUrl: loadUrl(call)
        }
    }
    
    init(withChannel channel: FlutterMethodChannel) {
        self.channel = channel
        webView = WKWebView(frame: .zero, configuration: configuration)
        
        super.init()
        
        initWebView()
        
        print("Initialized!!")
    }
    
    private func initWebView() {
        if #available(iOS 9.0, *) {
            configuration.allowsPictureInPictureMediaPlayback = false
            configuration.requiresUserActionForMediaPlayback = true
        }
        
        if #available(iOS 10.0, *) {
            configuration.mediaTypesRequiringUserActionForPlayback = .all
        }
        
        configuration.allowsInlineMediaPlayback = true
        
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        configuration.preferences = preferences
        
        configuration.userContentController.add(self, name: "native")
        webView.isHidden = true
        webView.navigationDelegate = self
    }
}

extension SwiftInteractiveWebviewPlugin {
    
    private func setupOptions(_ call: FlutterMethodCall) {
        guard let arguments = call.arguments as? [String: Any] else { return }
        
        if let restrictedSchemes = arguments["restrictedSchemes"] as? [String] {
            self.restrictedSchemes = restrictedSchemes
        }
    }
    
    private func evalJavascript(_ call: FlutterMethodCall) {
        guard
            let arguments = call.arguments as? [String: Any],
            let script = arguments["script"] as? String
            else { return }
        
        validateWebView()
        
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    private func loadHTML(_ call: FlutterMethodCall) {
        guard
            let arguments = call.arguments as? [String: Any],
            let html = arguments["html"] as? String
            else { return }
        
        validateWebView()
        
        if let baseUrlString = arguments["baseUrl"] as? String {
            webView.loadHTMLString(html, baseURL: URL(string: baseUrlString))
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
    
    private func loadUrl(_ call: FlutterMethodCall) {
        guard
            let arguments = call.arguments as? [String: Any],
            let urlString = arguments["url"] as? String,
            let url = URL(string: urlString)
            else { return }
        
        validateWebView()
        
        
        var request = URLRequest(url: url)

        var requestHeaders = [String:String]()

        let headers = arguments["headers"] as? NSDictionary

        if (headers != nil) {
            headers!.forEach { entry in
                let (key, value) = entry
                requestHeaders[String(describing: key)] = String(describing: value)
            }
            request.allHTTPHeaderFields = requestHeaders
        }
        
        webView.load(request)
    }
    
    private func validateWebView() {
        if webView.superview == nil {
            UIApplication.shared.keyWindow?.addSubview(webView)
        }
    }
}

extension SwiftInteractiveWebviewPlugin: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(decidePolicyForRequest(navigationAction.request))
    }
    
    private func decidePolicyForRequest(_ request: URLRequest) -> WKNavigationActionPolicy {
        if let url = request.url {
            let link = url.absoluteString
            
            // restrict schemes
            for l in restrictedSchemes {
                if link.contains(l) {
//                    return .canel
                    return .allow // My current app needs to follow redirects -> TODO: followRedirects variable
                }
            }
        }
        
        return .allow
    }
    
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
//        print("commit")
    }
    
    public func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
//        print(error.localizedDescription)
    }
    
    public func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
        channel.invokeMethod("stateChanged", arguments: ["type": "didFinish", "url": webView.url!.absoluteString])
    }
    
    public func webView(_: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        channel.invokeMethod("stateChanged", arguments: ["type": "didStart", "url": webView.url!.absoluteString])
    }

}

extension SwiftInteractiveWebviewPlugin: WKScriptMessageHandler {
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        
        if let data = body.data(using: .utf8),
            let jsonObj = try? JSONSerialization.jsonObject(with: data, options: .allowFragments) {
            channel.invokeMethod("didReceiveMessage", arguments: ["name": message.name, "data": jsonObj])
        } else {
            channel.invokeMethod("didReceiveMessage", arguments: ["name": message.name, "data": body])
        }
    }
}





