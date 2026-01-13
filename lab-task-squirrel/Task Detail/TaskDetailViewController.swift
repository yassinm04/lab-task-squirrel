//
//  TaskDetailViewController.swift
//  lab-task-squirrel
//
//  Created by Charlie Hieger on 11/15/22.
//

import UIKit
import MapKit
import PhotosUI
import Photos
import UniformTypeIdentifiers
import CoreLocation

class TaskDetailViewController: UIViewController, MKMapViewDelegate {

    @IBOutlet private weak var completedImageView: UIImageView!
    @IBOutlet private weak var completedLabel: UILabel!
    @IBOutlet private weak var titleLabel: UILabel!
    @IBOutlet private weak var descriptionLabel: UILabel!
    @IBOutlet private weak var attachPhotoButton: UIButton!

    // MapView outlet
    @IBOutlet private weak var mapView: MKMapView!

    // Programmatic "View Photo" button reference. We create it at runtime so storyboard edits aren't required.
    private var viewPhotoButton: UIButton?

    var task: Task!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Register custom annotation view so the map can dequeue our `TaskAnnotationView` instances
        mapView.register(TaskAnnotationView.self, forAnnotationViewWithReuseIdentifier: TaskAnnotationView.identifier)

        // Set the map view delegate to self so we can return custom annotation views
        mapView.delegate = self

        // UI Candy
        mapView.layer.cornerRadius = 12

        // Create the "View Photo" button programmatically and place it beneath the map view.
        if viewPhotoButton == nil {
            let bp = UIButton(type: .system)
            bp.translatesAutoresizingMaskIntoConstraints = false
            bp.setTitle("View Photo", for: .normal)
            bp.tintColor = .systemBlue
            if #available(iOS 15.0, *) {
                var config = UIButton.Configuration.filled()
                config.title = "View Photo"
                bp.configuration = config
            }
            bp.addTarget(self, action: #selector(didTapViewPhoto(_:)), for: .touchUpInside)
            view.addSubview(bp)

            NSLayoutConstraint.activate([
                bp.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: 12),
                bp.leadingAnchor.constraint(equalTo: mapView.leadingAnchor),
                bp.trailingAnchor.constraint(equalTo: mapView.trailingAnchor),
                bp.heightAnchor.constraint(equalToConstant: 34)
            ])

            viewPhotoButton = bp
        }

        updateUI()
        updateMapView()
    }

    /// Configure UI for the given task
    private func updateUI() {
        titleLabel.text = task.title
        descriptionLabel.text = task.description

        let completedImage = UIImage(systemName: task.isComplete ? "inset.filled.circle" : "circle")

        // calling `withRenderingMode(.alwaysTemplate)` on an image allows for coloring the image via it's `tintColor` property.
        completedImageView.image = completedImage?.withRenderingMode(.alwaysTemplate)
        completedLabel.text = task.isComplete ? "Complete" : "Incomplete"

        let color: UIColor = task.isComplete ? .systemBlue : .tertiaryLabel
        completedImageView.tintColor = color
        completedLabel.textColor = color

        mapView.isHidden = !task.isComplete
        attachPhotoButton.isHidden = task.isComplete
        viewPhotoButton?.isHidden = !task.isComplete
    }

    @IBAction func didTapAttachPhotoButton(_ sender: Any) {
        // Immediate visible feedback so user sees the tap registered and we avoid alerts blocking presentation.
        print("[TaskDetail] didTapAttachPhotoButton fired — updating button UI and attempting safe presentation")

        // Animate a quick title change on the button to show progress
        let originalTitle = attachPhotoButton.title(for: .normal)
        attachPhotoButton.setTitle("Opening…", for: .normal)
        attachPhotoButton.isEnabled = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self = self else { return }
            // Use the safe presenter which will retry if presentation is blocked
            self.presentImagePickerSafely()

            // Restore button state shortly after attempting presentation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.attachPhotoButton.setTitle(originalTitle, for: .normal)
                self.attachPhotoButton.isEnabled = true
            }
        }
    }

    private func topMostViewController() -> UIViewController? {
        // Start from the key window's rootViewController and walk presentedViewController chain
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            // Fallback: search connected scenes for a key window's rootViewController
            return UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })?.rootViewController
         }

        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    private func presentImagePicker() {
        // Create the PHPickerViewController
        var configuration = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self

        DispatchQueue.main.async {
            guard let presenter = self.topMostViewController() else {
                print("[TaskDetail] Unable to find a presenter to show picker")
                let alert = UIAlertController(title: "Can't Open Photos", message: "Unable to present the photo picker right now. Please try again.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                    self.presentImagePickerSafely()
                })
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                self.present(alert, animated: true, completion: nil)
                return
            }

            // If the top-most controller is already the picker, do nothing
            if presenter is PHPickerViewController {
                print("[TaskDetail] Top-most VC is already PHPicker")
                return
            }

            if let presented = presenter.presentedViewController {
                print("[TaskDetail] Dismissing existing presented VC (\(type(of: presented))) before presenting picker from top-most")
                presented.dismiss(animated: false) {
                    presenter.present(picker, animated: true, completion: nil)
                }
            } else {
                print("[TaskDetail] Presenting picker from top-most presenter: \(type(of: presenter))")
                presenter.present(picker, animated: true, completion: nil)
            }
        }
    }

    private func presentImagePickerSafely() {
        // Small delay to ensure any system alerts have a chance to dismiss.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            if let presented = self.presentedViewController {
                // Dismiss short-lived modals (alerts) before presenting the picker
                presented.dismiss(animated: false) {
                    self.presentImagePicker()
                }
            } else {
                self.presentImagePicker()
            }
        }
    }

    func updateMapView() {
        // Make sure the task has image location.
        guard let imageLocation = task.imageLocation else {
            mapView.isHidden = true
            return
        }

        // Get the coordinate from the image location. This is the latitude / longitude of the location.
        let coordinate = imageLocation.coordinate

        // Set the map view's region based on the coordinate of the image.
        // The span represents the map's "zoom level". A smaller value yields a more "zoomed in" map area, while a larger value is more "zoomed out".
        let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        mapView.setRegion(region, animated: true)

        // Show the map and add an annotation at the image location
        mapView.isHidden = false
        mapView.removeAnnotations(mapView.annotations)
        let annotation = MKPointAnnotation()
        annotation.coordinate = coordinate
        annotation.title = task.title
        mapView.addAnnotation(annotation)
    }

    @objc private func didTapViewPhoto(_ sender: Any) {
        // Prefer storyboard segue if configured; otherwise push/present PhotoViewController programmatically.
        if let _ = storyboard?.instantiateViewController(withIdentifier: "PhotoViewController") as? PhotoViewController {
            // If the storyboard scene is wired, perform the segue (prepare(for:) will pass the task).
            if let _ = storyboard?.value(forKey: "instantiateInitialViewController") { /* noop */ }
        }

        // Programmatic fallback: create and push/present PhotoViewController
        let photoVC = PhotoViewController()
        photoVC.task = task
        if let nav = self.navigationController {
            nav.pushViewController(photoVC, animated: true)
        } else {
            present(photoVC, animated: true)
        }
    }

    // Prepare for storyboard segue (in case a storyboard segue with identifier "PhotoSegue" is used).
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "PhotoSegue" {
            if let photoVC = segue.destination as? PhotoViewController {
                photoVC.task = task
            }
        }
    }
}

// Conform to PHPickerViewControllerDelegate and handle picked image + metadata (location)
extension TaskDetailViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        // Dismiss the picker right away (as the snippet requested)
        picker.dismiss(animated: true)

        // Get the selected image asset (we allowed selectionLimit = 1)
        let result = results.first

        // Try to get image location from PHAsset and print coordinates if available
        if let assetId = result?.assetIdentifier {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            if let asset = assets.firstObject, let location = asset.location {
                print("📍 Image location coordinate: \(location.coordinate)")
            } else {
                print("No image location metadata available for the selected asset.")
            }
        } else {
            print("No asset identifier returned by PHPicker for the selected item.")
        }

        // Continue with existing provider-based loading logic
        guard let result = results.first else { return }
        let provider = result.itemProvider

        // Helper to update task with image and optional location
        func updateTask(with image: UIImage, location: CLLocation?) {
            DispatchQueue.main.async {
                self.task.image = image
                if let location = location { self.task.imageLocation = location }
                self.updateUI()
                self.updateMapView()
            }
        }

        // If we have an asset identifier, we can try to fetch PHAsset to read its location. If we don't have
        // Photos authorization we will request it here; presenting the picker doesn't require full Photos access.
        let assetId = result.assetIdentifier

        // Load UIImage from the item provider first
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] (object, error) in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.showAlert(for: error) }
                    return
                }

                guard let image = object as? UIImage else { return }

                // If we have an assetId, try to fetch the asset's location. If not available, request authorization.
                if let assetId = assetId {
                    func fetchLocationAndUpdate() {
                        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                        if let asset = assets.firstObject, let location = asset.location {
                            updateTask(with: image, location: location)
                        } else {
                            // No location available or couldn't access it
                            updateTask(with: image, location: nil)
                        }
                    }

                    // Check current authorization for metadata access
                    let status: PHAuthorizationStatus = {
                        if #available(iOS 14, *) {
                            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
                        } else {
                            return PHPhotoLibrary.authorizationStatus()
                        }
                    }()

                    switch status {
                    case .authorized, .limited:
                        fetchLocationAndUpdate()
                    case .notDetermined:
                        if #available(iOS 14, *) {
                            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                                if newStatus == .authorized || newStatus == .limited {
                                    fetchLocationAndUpdate()
                                } else {
                                    updateTask(with: image, location: nil)
                                }
                            }
                        } else {
                            PHPhotoLibrary.requestAuthorization { newStatus in
                                if newStatus == .authorized {
                                    fetchLocationAndUpdate()
                                } else {
                                    updateTask(with: image, location: nil)
                                }
                            }
                        }
                    case .denied, .restricted:
                        // Can't access metadata — still update with image only
                        updateTask(with: image, location: nil)
                    @unknown default:
                        // Handle any future cases the same as denied/restricted
                        updateTask(with: image, location: nil)
                    }

                } else {
                    // No asset identifier – update with image only
                    updateTask(with: image, location: nil)
                }
            }

        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            // Fallback: load raw image data
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, error in
                guard let self = self else { return }
                if let error = error {
                    DispatchQueue.main.async { self.showAlert(for: error) }
                    return
                }

                guard let data = data, let image = UIImage(data: data) else { return }

                // If there's an asset identifier, attempt to fetch its location similar to above
                if let assetId = assetId {
                    func fetchLocationAndUpdate() {
                        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                        if let asset = assets.firstObject, let location = asset.location {
                            updateTask(with: image, location: location)
                        } else {
                            updateTask(with: image, location: nil)
                        }
                    }

                    let status: PHAuthorizationStatus = {
                        if #available(iOS 14, *) {
                            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
                        } else {
                            return PHPhotoLibrary.authorizationStatus()
                        }
                    }()

                    switch status {
                    case .authorized, .limited:
                        fetchLocationAndUpdate()
                    case .notDetermined:
                        if #available(iOS 14, *) {
                            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                                if newStatus == .authorized || newStatus == .limited {
                                    fetchLocationAndUpdate()
                                } else {
                                    updateTask(with: image, location: nil)
                                }
                            }
                        } else {
                            PHPhotoLibrary.requestAuthorization { newStatus in
                                if newStatus == .authorized {
                                    fetchLocationAndUpdate()
                                } else {
                                    updateTask(with: image, location: nil)
                                }
                            }
                        }
                    case .denied, .restricted:
                        updateTask(with: image, location: nil)
                    @unknown default:
                        updateTask(with: image, location: nil)
                    }
                } else {
                    updateTask(with: image, location: nil)
                }
            }
        }
    }
}

// TODO: Conform to MKMapKitDelegate + implement mapView(_:viewFor:) delegate method.

// Helper methods to present various alerts
extension TaskDetailViewController {

    /// Presents an alert notifying user of photo library access requirement with an option to go to Settings in order to update status.
    func presentGoToSettingsAlert() {
        let alertController = UIAlertController (
            title: "Photo Access Required",
            message: "In order to post a photo to complete a task, we need access to your photo library. You can allow access in Settings",
            preferredStyle: .alert)

        let settingsAction = UIAlertAction(title: "Settings", style: .default) { _ in
            guard let settingsUrl = URL(string: UIApplication.openSettingsURLString) else { return }

            if UIApplication.shared.canOpenURL(settingsUrl) {
                UIApplication.shared.open(settingsUrl)
            }
        }

        alertController.addAction(settingsAction)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)

        present(alertController, animated: true, completion: nil)
    }

    /// Show an alert for the given error
    private func showAlert(for error: Error? = nil) {
        let alertController = UIAlertController(
            title: "Oops...",
            message: "\(error?.localizedDescription ?? "Please try again...")",
            preferredStyle: .alert)

        let action = UIAlertAction(title: "OK", style: .default)
        alertController.addAction(action)

        present(alertController, animated: true)
    }
}
