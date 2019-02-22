//
//  Camera.swift
//  NotificationContentExtension
//
//  Created by Robert Trencheny on 10/2/18.
//  Copyright © 2018 Robbie Trencheny. All rights reserved.
//

import UIKit
import UserNotifications
import UserNotificationsUI
import MBProgressHUD
import KeychainAccess
import Shared
import Alamofire
import AlamofireImage

class CameraViewController: UIView, NotificationCategory {
    private var baseURL: URL = Current.settingsStore.connectionInfo!.activeAPIURL

    let urlConfiguration: URLSessionConfiguration = URLSessionConfiguration.default

    var parentView: UIView = UIView(frame: .zero)

    var shouldPlay: Bool = true

    var streamer: MJPEGStreamer?

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func didReceive(_ notification: UNNotification, view: UIView, extensionContext: NSExtensionContext?,
                    hud: MBProgressHUD, completionHandler: @escaping (String?) -> Void) {

        view.accessibilityIdentifier = "camera_notification"

        parentView = view

        guard let entityId = notification.request.content.userInfo["entity_id"] as? String else {
            completionHandler(L10n.Extensions.NotificationContent.Error.noEntityId)
            return
        }
        //        guard let cameraProxyURL = baseURL.appendPathComponent("camera_proxy_stream/\(entityId)") else {
        //            self.showErrorLabel(message: "Could not form a valid URL!")
        //            return
        //        }

        guard let api = HomeAssistantAPI.authenticatedAPI() else {
            completionHandler(HomeAssistantAPI.APIError.notConfigured.localizedDescription)
            return
        }

        let imageView = UIImageView()
        imageView.frame = view.frame
        imageView.accessibilityIdentifier = "camera_notification_imageview"

        var frameCount = 0

        guard let streamer = api.videoStreamer() else {
            return
        }

        self.streamer = streamer
        let apiURL = api.connectionInfo.activeAPIURL
        let queryUrl = apiURL.appendingPathComponent("camera_proxy_stream/\(entityId)", isDirectory: false)

        streamer.streamImages(fromURL: queryUrl) { (image, error) in
            if let error = error, let afError = error as? AFError {
                Current.Log.error("Streaming image AFError: \(afError)")
                var labelText = L10n.Extensions.NotificationContent.Error.Request.unknown
                if let responseCode = afError.responseCode {
                    switch responseCode {
                    case 401:
                        labelText = L10n.Extensions.NotificationContent.Error.Request.authFailed
                    case 404:
                        labelText = L10n.Extensions.NotificationContent.Error.Request.entityNotFound(entityId)
                    default:
                        labelText = L10n.Extensions.NotificationContent.Error.Request.other(responseCode)
                    }
                }
                completionHandler(labelText)
            }

            if let image = image {
                defer {
                    frameCount += 1
                    Current.Log.verbose("FRAME \(frameCount)")
                }
                if frameCount == 0 {
                    Current.Log.verbose("Got first frame!")

                    Current.Log.verbose("Finished loading")

                    DispatchQueue.main.async(execute: {
                        hud.hide(animated: true)
                    })

                    view.addSubview(imageView)

                    //            streamingController?.play()
                    extensionContext?.mediaPlayingStarted()
                }

                if self.shouldPlay {
                    image.accessibilityIdentifier = "camera_notification_image"
                    imageView.image = image
                    imageView.image?.accessibilityIdentifier = image.accessibilityIdentifier
                }
            }

        }

        completionHandler(nil)
    }

    var isMediaExtension: Bool {
        return true
    }

    var mediaPlayPauseButtonType: UNNotificationContentExtensionMediaPlayPauseButtonType {
        return .overlay
    }

    var mediaPlayPauseButtonFrame: CGRect {
        let centerX = Double(parentView.frame.width) / 2.0
        let centerY = Double(parentView.frame.height) / 2.0
        let buttonWidth = 50.0
        let buttonHeight = 50.0
        return CGRect(x: centerX - buttonWidth/2.0, y: centerY - buttonHeight/2.0,
                      width: buttonWidth, height: buttonHeight)
    }

    public func mediaPlay() {
        self.shouldPlay = true
    }

    public func mediaPause() {
        self.shouldPlay = false
    }

}
