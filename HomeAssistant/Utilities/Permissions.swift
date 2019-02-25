//
//  Permissions.swift
//  HomeAssistant
//
//  Created by Robert Trencheny on 10/6/18.
//  Copyright © 2018 Robbie Trencheny. All rights reserved.
//

import Foundation
import arek
import Shared
import UserNotifications

var arekConfig: ArekConfiguration {
    return ArekConfiguration(frequency: .Always, presentInitialPopup: true, presentReEnablePopup: true)
}

func LocationPermission() -> ArekLocationAlways {
    let initialPopupData = ArekPopupData(title: L10n.Permissions.Location.Initial.title,
                                         message: L10n.Permissions.Location.Initial.message,
                                         image: "",
                                         allowButtonTitle: L10n.Permissions.Location.Initial.Button.allow,
                                         denyButtonTitle: L10n.Permissions.Location.Initial.Button.deny,
                                         type: .native,
                                         styling: nil)

    let reEnablePopupData = ArekPopupData(title: L10n.Permissions.Location.Reenable.title,
                                          message: L10n.Permissions.Location.Reenable.message,
                                          image: "",
                                          allowButtonTitle: L10n.Permissions.Location.Reenable.Button.allow,
                                          denyButtonTitle: L10n.Permissions.Location.Reenable.Button.deny,
                                          type: .native,
                                          styling: nil)

    return ArekLocationAlways(configuration: arekConfig, initialPopupData: initialPopupData,
                             reEnablePopupData: reEnablePopupData)
}

func MotionPermission() -> ArekMotion {
    let initialPopupData = ArekPopupData(title: L10n.Permissions.Motion.Initial.title,
                                         message: L10n.Permissions.Motion.Initial.message,
                                         image: "",
                                         allowButtonTitle: L10n.Permissions.Motion.Initial.Button.allow,
                                         denyButtonTitle: L10n.Permissions.Motion.Initial.Button.deny,
                                         type: .native,
                                         styling: nil)

    let reEnablePopupData = ArekPopupData(title: L10n.Permissions.Motion.Reenable.title,
                                          message: L10n.Permissions.Motion.Reenable.message,
                                          image: "",
                                          allowButtonTitle: L10n.Permissions.Motion.Reenable.Button.allow,
                                          denyButtonTitle: L10n.Permissions.Motion.Reenable.Button.deny,
                                          type: .native,
                                          styling: nil)

    return ArekMotion(configuration: arekConfig, initialPopupData: initialPopupData,
                      reEnablePopupData: reEnablePopupData)
}

func NotificationPermission() -> ArekNotifications {
    let initialPopupData = ArekPopupData(title: L10n.Permissions.Notification.Initial.title,
                                         message: L10n.Permissions.Notification.Initial.message,
                                         image: "",
                                         allowButtonTitle: L10n.Permissions.Notification.Initial.Button.allow,
                                         denyButtonTitle: L10n.Permissions.Notification.Initial.Button.deny,
                                         type: .native,
                                         styling: nil)

    let reEnablePopupData = ArekPopupData(title: L10n.Permissions.Notification.Reenable.title,
                                          message: L10n.Permissions.Notification.Reenable.message,
                                          image: "",
                                          allowButtonTitle: L10n.Permissions.Notification.Reenable.Button.allow,
                                          denyButtonTitle: L10n.Permissions.Notification.Reenable.Button.deny,
                                          type: .native,
                                          styling: nil)

    var opts: UNAuthorizationOptions = [.alert, .badge, .sound]

    if #available(iOS 12.0, *) {
        opts = [.alert, .badge, .sound, .criticalAlert, .providesAppNotificationSettings]
    }

    return ArekNotifications(configuration: arekConfig, initialPopupData: initialPopupData,
                             reEnablePopupData: reEnablePopupData, notificationOptions: opts)
}

func CheckPermissionsStatus() {
    Current.Log.verbose("Checking permissions status!")

    LocationPermission().status { (status) in
        Current.Log.verbose("Location status: \(status)")

        if status == .notDetermined || Current.settingsStore.locationEnabled != (status == .authorized) {
            EnsureLocationPermission()
        }
    }

    MotionPermission().status { (status) in
        Current.Log.verbose("Motion status: \(status)")

        if status == .notDetermined || Current.settingsStore.motionEnabled != (status == .authorized) {
            EnsureMotionPermission()
        }
    }

    NotificationPermission().status { (status) in
        Current.Log.verbose("Notifications status: \(status)")

        if status == .notDetermined || Current.settingsStore.notificationsEnabled != (status == .authorized) {
            EnsureNotificationPermission()
        }
    }
}

func EnsureLocationPermission() {
    LocationPermission().manage { (status) in
        Current.Log.verbose("Location status: \(status)")

        if Current.settingsStore.locationEnabled != (status == .authorized) {
            Current.settingsStore.locationEnabled = (status == .authorized)

            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "permission_change"),
                                            object: nil,
                                            userInfo: ["location": Current.settingsStore.locationEnabled])
        }
    }
}

func EnsureMotionPermission() {
    MotionPermission().manage { (status) in
        Current.Log.verbose("Motion status: \(status)")

        if Current.settingsStore.motionEnabled != (status == .authorized) {
            Current.settingsStore.motionEnabled = (status == .authorized)

            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "permission_change"),
                                            object: nil,
                                            userInfo: ["motion": Current.settingsStore.motionEnabled])
        }
    }
}

func EnsureNotificationPermission() {
    NotificationPermission().manage { (status) in
        Current.Log.verbose("Notifications status: \(status)")

        if Current.settingsStore.notificationsEnabled != (status == .authorized) {
            Current.settingsStore.notificationsEnabled = (status == .authorized)

            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "permission_change"),
                                            object: nil,
                                            userInfo: ["notifications": Current.settingsStore.notificationsEnabled])
        }
    }
}
