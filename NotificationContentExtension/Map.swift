//
//  Map.swift
//  NotificationContentExtension
//
//  Created by Robert Trencheny on 10/2/18.
//  Copyright © 2018 Robbie Trencheny. All rights reserved.
//

import UIKit
import UserNotifications
import UserNotificationsUI
import MapKit
import MBProgressHUD

class MapViewController: UIView, NotificationCategory, MKMapViewDelegate {

    var view: UIView = UIView(frame: .zero)

    var mapView: MKMapView!

    // swiftlint:disable:next function_body_length
    func didReceive(_ notification: UNNotification, vc: UIViewController, extensionContext: NSExtensionContext?,
                    hud: MBProgressHUD, completionHandler: @escaping (String?) -> Void) {

        let userInfo = notification.request.content.userInfo

        guard let haDict = userInfo["homeassistant"] as? [String: Any] else {
            completionHandler(L10n.Extensions.Map.PayloadMissingHomeassistant.message)
            return
        }
        guard let latitudeString = haDict["latitude"] as? String else {
            completionHandler(L10n.Extensions.Map.ValueMissingOrUncastable.Latitude.message)
            return
        }
        guard let longitudeString = haDict["longitude"] as? String else {
            completionHandler(L10n.Extensions.Map.ValueMissingOrUncastable.Longitude.message)
            return
        }
        let latitude = Double.init(latitudeString)! as CLLocationDegrees
        let longitude = Double.init(longitudeString)! as CLLocationDegrees
        let location = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.mapView = MKMapView()

        self.mapView.delegate = self
        self.mapView.mapType = .standard
        self.mapView.frame = vc.view.frame

        self.mapView.showsUserLocation = (haDict["shows_user_location"] != nil)
        self.mapView.pointOfInterestFilter = haDict["shows_points_of_interest"] != nil ? .includingAll : .excludingAll
        self.mapView.showsCompass = (haDict["shows_compass"] != nil)
        self.mapView.showsScale = (haDict["shows_scale"] != nil)
        self.mapView.showsTraffic = (haDict["shows_traffic"] != nil)

        self.mapView.accessibilityIdentifier = "notification_map"

        let span = MKCoordinateSpan.init(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let region = MKCoordinateRegion(center: location, span: span)
        self.mapView.setRegion(region, animated: true)
        vc.view.addSubview(self.mapView)

        let dropPin = MKPointAnnotation()
        dropPin.coordinate = location

        if let secondLatitudeString = haDict["second_latitude"] as? String,
            let secondLongitudeString = haDict["second_longitude"] as? String {
            let secondLatitude = Double.init(secondLatitudeString)! as CLLocationDegrees
            let secondLongitude = Double.init(secondLongitudeString)! as CLLocationDegrees
            let secondDropPin = MKPointAnnotation()
            secondDropPin.coordinate = CLLocationCoordinate2D(latitude: secondLatitude, longitude: secondLongitude)
            secondDropPin.title = L10n.Extensions.Map.Location.new
            self.mapView.addAnnotation(secondDropPin)

            self.mapView.selectAnnotation(secondDropPin, animated: true)

            dropPin.title = L10n.Extensions.Map.Location.original
        }

        self.mapView.addAnnotation(dropPin)

        if mapView.annotations.count > 1 {
            if haDict["shows_line_between_points"] != nil {
                var polylinePoints: [CLLocationCoordinate2D] = [CLLocationCoordinate2D]()

                for annotation in self.mapView.annotations {
                    polylinePoints.append(annotation.coordinate)
                }
                self.mapView.addOverlay(MKPolyline(coordinates: &polylinePoints, count: polylinePoints.count))
            }

            mapView.showAnnotations(mapView.annotations, animated: true)
            mapView.camera.altitude *= 1.4
        }

        completionHandler(nil)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            //if annotation is not an MKPointAnnotation (eg. MKUserLocation),
            //return nil so map draws default view for it (eg. blue dot)...
            return nil
        }

        let pinView: MKPinAnnotationView = MKPinAnnotationView()
        pinView.annotation = annotation
        if let title = annotation.title {
            if title == L10n.Extensions.Map.Location.original {
                pinView.pinTintColor = .red
            } else if title == L10n.Extensions.Map.Location.new {
                pinView.pinTintColor = .green
            }
        } else {
            pinView.pinTintColor = .red
        }
        pinView.animatesDrop = true
        pinView.canShowCallout = true

        return pinView
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let polylineRenderer = MKPolylineRenderer(overlay: overlay)
        polylineRenderer.strokeColor = UIColor.red
        polylineRenderer.fillColor = UIColor.red.withAlphaComponent(0.1)
        polylineRenderer.lineWidth = 1
        polylineRenderer.lineDashPattern = [2, 5]
        return polylineRenderer
    }
}
