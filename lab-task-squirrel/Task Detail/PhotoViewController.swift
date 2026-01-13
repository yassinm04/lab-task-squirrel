import UIKit

class PhotoViewController: UIViewController {
    
    @IBOutlet weak var photoView: UIImageView!
    
    var task: Task!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // If the image view outlet hasn't been connected (e.g. when this VC is instantiated programmatically),
        // create and pin an image view to the view controller's view.
        if photoView == nil {
            let iv = UIImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.contentMode = .scaleAspectFit
            view.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                iv.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                iv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                iv.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
            photoView = iv
        }

        // Set the image from the task (if available)
        photoView.image = task?.image
        view.backgroundColor = .systemBackground

        // If this controller is presented modally (either directly or wrapped in a UINavigationController),
        // add a Done button so it can be dismissed. We check `presentingViewController` and the nav wrapper.
        let isPresentedModally = presentingViewController != nil || navigationController?.presentingViewController != nil
        if isPresentedModally {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(didTapDone))
        }
    }

    @objc func didTapDone() {
        dismiss(animated: true, completion: nil)
    }
}
