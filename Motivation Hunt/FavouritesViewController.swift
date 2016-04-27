//
//  FavouritesViewController.swift
//  Motivation Hunt
//
//  Created by Jefferson Bonnaire on 27/02/2016.
//  Copyright © 2016 Jefferson Bonnaire. All rights reserved.
//

import UIKit
import CoreData
import YouTubePlayer
import CloudKit
import Toucan
import Async
import TBEmptyDataSet

class FavouritesViewController: UIViewController {

    var collectionView: UICollectionView!
    var indicator = CustomUIActivityIndicatorView()
    var shouldReloadCollectionView = false
    var blockOperations: [NSBlockOperation] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()

        // Initialize delegate
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.emptyDataSetDataSource = self
        collectionView.emptyDataSetDelegate = self
        fetchedResultsController.delegate = self

        // Configure CollectionView
        collectionView.registerClass(motivationCollectionViewCell.self, forCellWithReuseIdentifier: MHClient.CellIdentifier.cellWithReuseIdentifier)
        collectionView.backgroundColor = UIColor.clearColor()
        collectionView.allowsMultipleSelection = false

        view.backgroundColor = UIColor(patternImage: UIImage(named: "backgroundFeed.png")!)
        let blurEffect = UIBlurEffect(style: UIBlurEffectStyle.Dark)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)
        blurEffectView.frame = view.bounds
        blurEffectView.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
        view.insertSubview(blurEffectView, belowSubview: collectionView)

        do {
            try fetchedResultsController.performFetch()
        } catch let error as NSError {
            print("Error: \(error.localizedDescription)")
        }
    }

    // Initialize CoreData and NSFetchedResultsController

    var sharedContext: NSManagedObjectContext {
        return CoreDataStackManager.sharedInstance.managedObjectContext
    }

    lazy var fetchedResultsController: NSFetchedResultsController = {

        let fetchRequest = NSFetchRequest(entityName: "MotivationFeedItem")
        let predicate = NSPredicate(format: "saved == 1")
        fetchRequest.predicate = predicate
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "itemID", ascending: true)]

        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: self.sharedContext,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        
        return fetchedResultsController
    }()

    deinit {
        // Cancel all block operations when VC deallocates
        for operation: NSBlockOperation in blockOperations {
            operation.cancel()
        }

        blockOperations.removeAll(keepCapacity: false)
    }
}

extension FavouritesViewController {

    override func viewDidLayoutSubviews() {
        if let rectNavigationBar = navigationController?.navigationBar.frame, let rectTabBar = tabBarController?.tabBar.frame  {
            let navigationBarSpace = rectNavigationBar.size.height + rectNavigationBar.origin.y
            let tabBarSpace = rectTabBar.size.height + rectTabBar.origin.x
            collectionView.contentInset = UIEdgeInsetsMake(navigationBarSpace, 0, tabBarSpace, 0)
        }
    }

    func setupUI() {
        // Configure CollectionView
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.registerClass(motivationCollectionViewCell.self, forCellWithReuseIdentifier: MHClient.CellIdentifier.cellWithReuseIdentifier)
        collectionView.backgroundColor = UIColor.clearColor()
        collectionView.allowsMultipleSelection = false
        view.addSubview(collectionView)
        collectionView.snp_makeConstraints { (make) in
            make.top.equalTo(view)
            make.width.equalTo(view)
            make.bottom.equalTo(view.snp_bottom)
            make.center.equalTo(view)
        }
    }

    override func willRotateToInterfaceOrientation(toInterfaceOrientation: UIInterfaceOrientation, duration: NSTimeInterval) {
        collectionView.collectionViewLayout.invalidateLayout()
    }

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {}
}

extension FavouritesViewController {
    func savedItem(gestureRecognizer: UIGestureRecognizer) {
        let tapPoint: CGPoint = gestureRecognizer.locationInView(collectionView)
        let indexPath = collectionView.indexPathForItemAtPoint(tapPoint)
        let objet = fetchedResultsController.objectAtIndexPath(indexPath!) as! MotivationFeedItem

        Async.main {
            objet.saved = objet.saved ? false : true
            CoreDataStackManager.sharedInstance.saveContext()
        }

        CloudKitHelper.sharedInstance.updateFavorites(CKRecordID(recordName: objet.itemRecordID)) { (success, record, error) in
            guard error == nil else {
                return
            }
        }
    }

    func playVideo(gestureRecognizer: UIGestureRecognizer) {
        let tapPoint: CGPoint = gestureRecognizer.locationInView(collectionView)
        let indexPath = collectionView.indexPathForItemAtPoint(tapPoint)
        let cell = collectionView.cellForItemAtIndexPath(indexPath!) as! motivationCollectionViewCell
        cell.videoPlayer.play()
        UIView.animateWithDuration(0.5, delay: 0.0, options: UIViewAnimationOptions.CurveEaseOut, animations: {
            cell.videoPlayer.alpha = 1
            cell.playButton.alpha = 0
            cell.imageView.alpha = 0
            }, completion: nil)
    }

    func shareMotivation(gestureRecognizer: UIGestureRecognizer) {
        let tapPoint: CGPoint = gestureRecognizer.locationInView(collectionView)
        let indexPath = collectionView.indexPathForItemAtPoint(tapPoint)
        let cell = collectionView.cellForItemAtIndexPath(indexPath!) as! motivationCollectionViewCell
        let motivation = fetchedResultsController.objectAtIndexPath(indexPath!) as! MotivationFeedItem
        let motivationToShare = [motivation.itemTitle, motivation.itemDescription, "https://www.youtube.com/watch?v=\(motivation.itemID)"]
        let activityViewController = UIActivityViewController(activityItems: motivationToShare, applicationActivities: nil)
        activityViewController.excludedActivityTypes = [UIActivityTypeAirDrop, UIActivityTypeAddToReadingList]

        activityViewController.popoverPresentationController?.sourceView = cell.imageView
        activityViewController.popoverPresentationController?.sourceRect = cell.imageView.bounds

        self.presentViewController(activityViewController, animated: true, completion: nil)
    }
}

extension FavouritesViewController: TBEmptyDataSetDataSource, TBEmptyDataSetDelegate {
    func titleForEmptyDataSet(scrollView: UIScrollView!) -> NSAttributedString? {
        // return the description for EmptyDataSet
        let title = "You don't have any favourites"
        let attributes = [NSFontAttributeName: UIFont.systemFontOfSize(24.0), NSForegroundColorAttributeName: UIColor.grayColor()]
        return NSAttributedString(string: title, attributes: attributes)
    }

    func imageForEmptyDataSet(scrollView: UIScrollView!) -> UIImage? {
        let image = UIImage(named: "iconFeatured")
        return image
    }

    func descriptionForEmptyDataSet(scrollView: UIScrollView!) -> NSAttributedString? {
        let title = "Add a favourites to watch later!"
        let attributes = [NSFontAttributeName: UIFont.systemFontOfSize(18.00), NSForegroundColorAttributeName: UIColor.grayColor()]
        return NSAttributedString(string: title, attributes: attributes)
    }

    func emptyDataSetShouldDisplay(scrollView: UIScrollView!) -> Bool {
        guard fetchedResultsController.fetchedObjects?.count == 0 else {
            return false
        }
        return true
    }
}

extension FavouritesViewController: UICollectionViewDelegate, UICollectionViewDataSource {

    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let sectionInfo = fetchedResultsController.sections![section] as NSFetchedResultsSectionInfo
        return sectionInfo.numberOfObjects
    }

    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let motivationItem = fetchedResultsController.objectAtIndexPath(indexPath) as! MotivationFeedItem
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(MHClient.CellIdentifier.cellWithReuseIdentifier, forIndexPath: indexPath) as! motivationCollectionViewCell
        configureCell(cell, withItem: motivationItem)
        return cell
    }

    func configureCell(cell: motivationCollectionViewCell, withItem item: MotivationFeedItem) {
        cell.videoPlayer.delegate = self
        cell.textLabel.text = item.itemTitle

        let playVideoOnTapPlayButton: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(playVideo(_:)))
        playVideoOnTapPlayButton.numberOfTapsRequired = 1
        cell.playButton.addGestureRecognizer(playVideoOnTapPlayButton)

        let playVideoOnTapImageView: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(playVideo(_:)))
        playVideoOnTapImageView.numberOfTapsRequired = 1
        cell.imageView.addGestureRecognizer(playVideoOnTapImageView)

        let tapToSavedItem: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(savedItem(_:)))
        tapToSavedItem.numberOfTapsRequired = 1
        cell.favoriteBarButton.addGestureRecognizer(tapToSavedItem)

        let shareOnTapshareBarButton: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(shareMotivation(_:)))
        shareOnTapshareBarButton.numberOfTapsRequired = 1
        cell.shareBarButton.addGestureRecognizer(shareOnTapshareBarButton)

        if item.saved {
            cell.favoriteBarButton.setTitle(String.fontAwesomeIconWithName(.Heart), forState: .Normal)
        } else {
            cell.favoriteBarButton.setTitle(String.fontAwesomeIconWithName(.HeartO), forState: .Normal)
        }

        if item.image == nil {
            MHClient.sharedInstance.taskForImage(item.itemThumbnailsUrl) { imageData, error in
                guard error == nil else {
                    return
                }
                Async.main {
                    item.image = UIImage(data: imageData!)
                }
            }
        }

        if item.image != nil {
            Async.main {
                cell.imageView.image = Toucan(image: item.image!).resize(CGSize(width: cell.frame.width - 10, height: cell.frame.width / 1.8), fitMode: Toucan.Resize.FitMode.Crop).maskWithRoundedRect(cornerRadius: 10).image
            }
        }
    }

    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        let device = UIDevice.currentDevice().model
        let dimensioniPhone = view.frame.width
        var cellSize: CGSize = CGSizeMake(dimensioniPhone, dimensioniPhone * 0.8)
        let dimensioniPad = (view.frame.width / 2) - 15

        if (device == "iPad" || device == "iPad Simulator") {
            cellSize = CGSizeMake(dimensioniPad, dimensioniPad * 0.8)
        }
        return cellSize
    }

    func collectionView(collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                               insetForSectionAtIndex section: Int) -> UIEdgeInsets {
        let device = UIDevice.currentDevice().model
        var edgeInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        if (device == "iPad" || device == "iPad Simulator") {
            edgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        }

        return edgeInsets
    }

    func collectionView(collectionView: UICollectionView, didEndDisplayingCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        if let cell = cell as? motivationCollectionViewCell {
            UIView.animateWithDuration(0.5, delay: 0.0, options: UIViewAnimationOptions.CurveEaseOut, animations: {
                cell.playButton.alpha = 0
                cell.imageView.alpha = 0
                }, completion: nil)
            cell.videoPlayer.stop()
        }
    }

    func collectionView(collectionView: UICollectionView, willDisplayCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        if let cell = cell as? motivationCollectionViewCell {
            let motivationItem = fetchedResultsController.objectAtIndexPath(indexPath) as! MotivationFeedItem
            cell.videoPlayer.loadVideoID(motivationItem.itemID)
            cell.imageView.alpha = 0
            cell.playButton.alpha = 0
            cell.videoPlayer.alpha = 0
            UIView.animateWithDuration(0.5, delay: 0.0, options: UIViewAnimationOptions.CurveEaseOut, animations: {
                cell.imageView.alpha = 1
                cell.playButton.alpha = 0.7
                }, completion: nil)
        }
    }
}

extension FavouritesViewController: YouTubePlayerDelegate {
    func playerStateChanged(videoPlayer: YouTubePlayerView, playerState: YouTubePlayerState) {
        if playerState == .Buffering {
            indicator.startActivity()
            view.addSubview(indicator)
        }

        if playerState == .Playing {
            indicator.stopActivity()
            indicator.removeFromSuperview()
        }
    }

    func playerQualityChanged(videoPlayer: YouTubePlayerView, playbackQuality: YouTubePlaybackQuality) {}
    func playerReady(videoPlayer: YouTubePlayerView) {}
}


extension FavouritesViewController: NSFetchedResultsControllerDelegate {
    func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
        switch (type) {
        case .Insert:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.insertItemsAtIndexPaths([newIndexPath!])
                    }
                    })
            )
        case .Update:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.reloadItemsAtIndexPaths([indexPath!])
                    }
                    })
            )
        case .Move:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.moveItemAtIndexPath(indexPath!, toIndexPath: newIndexPath!)
                    }
                    })
            )
        case .Delete:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.deleteItemsAtIndexPaths([indexPath!])
                    }
                    })
            )
        }
    }

    func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
        switch (type) {
        case .Insert:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.insertSections(NSIndexSet(index: sectionIndex))
                    }
                    })
            )
        case .Update:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.reloadSections(NSIndexSet(index: sectionIndex))
                    }
                    })
            )
        case .Delete:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.deleteSections(NSIndexSet(index: sectionIndex))
                    }
                    })
            )
        case .Move:
            blockOperations.append(
                NSBlockOperation(block: { [weak self] in
                    if let this = self {
                        this.collectionView!.moveSection(sectionIndex, toSection: sectionIndex)
                    }
                })
            )
        }
    }

    func controllerDidChangeContent(controller: NSFetchedResultsController) {
        collectionView!.performBatchUpdates({ () -> Void in
            for operation: NSBlockOperation in self.blockOperations {
                operation.start()
            }
            }, completion: { (finished) -> Void in
                self.blockOperations.removeAll(keepCapacity: false)
        })
        collectionView.reloadData()
    }
}