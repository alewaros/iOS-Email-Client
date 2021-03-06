//
//  EmailDetailViewController.swift
//  iOS-Email-Client
//
//  Created by Pedro Aim on 2/27/18.
//  Copyright © 2018 Criptext Inc. All rights reserved.
//
import Material
import Foundation
import Photos
import SafariServices
import Instructions

class EmailDetailViewController: UIViewController {
    let ESTIMATED_ROW_HEIGHT : CGFloat = 75
    let ESTIMATED_SECTION_HEADER_HEIGHT : CGFloat = 50
    let CONTACTS_BASE_HEIGHT = 70
    let CONTACTS_MAX_HEIGHT: CGFloat = 300.0
    let CONTACTS_ROW_HEIGHT = 28
    
    var isExpanded = false
    var emailData : EmailDetailData!
    weak var mailboxData : MailboxData!
    weak var myAccount: Account!
    @IBOutlet weak var webView: UIWebView!
    @IBOutlet weak var emailsTableView: UITableView!
    @IBOutlet weak var topToolbar: TopbarUIView!
    @IBOutlet weak var moreOptionsContainerView: DetailMoreOptionsUIView!
    @IBOutlet weak var generalOptionsContainerView: GeneralMoreOptionsUIView!
    
    weak var myHeaderView : UIView?
    weak var target: UIView?
    let fileManager = CriptextFileManager()
    let coachMarksController = CoachMarksController()
    
    var message: ControllerMessage?
    
    var theme: Theme {
        return ThemeManager.shared.theme
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.webView.delegate = self
        self.navigationController?.interactivePopGestureRecognizer?.delegate = self as UIGestureRecognizerDelegate
        self.setupToolbar()
        self.setupMoreOptionsViews()
        
        self.registerCellNibs()
        self.topToolbar.delegate = self
        self.generalOptionsContainerView.delegate = self
        fileManager.delegate = self
        fileManager.token = myAccount.jwt
        
        displayMarkIcon(asRead: false)
        generalOptionsContainerView.handleCurrentLabel(currentLabel: emailData.selectedLabel)
        
        self.coachMarksController.overlay.allowTap = true
        self.coachMarksController.overlay.color = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.85)
        self.coachMarksController.dataSource = self
        
        emailData.observerToken = emailData.emails.observe { [weak self] changes in
            guard let tableView = self?.emailsTableView else {
                return
            }
            switch(changes){
            case .initial:
                tableView.reloadData()
            case .update(_, _, let insertions, _):
                insertions.forEach({ (position) in
                    guard let email = self?.emailData.emails[position],
                        self?.emailData.bodies[email.key] == nil,
                        let myAccount = self?.myAccount else {
                            return
                    }
                    self?.emailData.bodies[email.key] = FileUtils.getBodyFromFile(account: myAccount, metadataKey: "\(email.key)")
                })
                tableView.reloadData()
                self?.emailData.rebuildLabels()
                let hasNewInboxEmail = insertions.contains(where: { (position) -> Bool in
                    guard let email = self?.emailData.emails[position],
                        email.labels.contains(where: {$0.id == SystemLabel.inbox.id}) else {
                            return false
                    }
                    return true
                })
                if (hasNewInboxEmail) {
                    self?.showSnackbar(String.localize("HAVE_NEW_EMAIL"), attributedText: nil, buttons: "", permanent: false)
                }
            default:
                break
            }
            
            guard let myself = self else {
                return
            }
            
            if(myself.emailData.emails.isEmpty){
                myself.mailboxData.removeSelectedRow = true
                myself.navigationController?.popViewController(animated: true)
            }
        }
        applyTheme()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        self.topToolbar.isHidden = true
        self.coachMarksController.stop(immediately: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.topToolbar.swapTrashIcon(labelId: emailData.selectedLabel)
        self.topToolbar.isHidden = false
        let defaults = CriptextDefaults()
        if !defaults.guideUnsend,
            let email = emailData.emails.first,
            email.isSent && emailData.getState(email.key).isExpanded && emailData.emails.count == 1 {
            self.coachMarksController.start(on: self)
            defaults.guideUnsend = true
        }
        
        handleControllerMessage(message)
    }
    
    func applyTheme() {
        let theme = ThemeManager.shared.theme
        self.view.backgroundColor = theme.background
        self.emailsTableView.backgroundColor = theme.background
        self.emailsTableView.reloadData()
    }
    
    func isGroupable() -> Bool {
        let emails = emailData.emails.filter(NSPredicate(format: "unread == true"))
        return (emailData.emails.count >= 4 && emails.count == 0 && !isExpanded)
    }
    
    func handleControllerMessage(_ message: ControllerMessage?) {
        guard let controllerMessage = message else {
            return
        }
        switch(controllerMessage){
        case .ReplyThread(let emailKey):
            guard let index = emailData.emails.firstIndex(where: {$0.key == emailKey}) else {
                break
            }
            emailsTableView.selectRow(at: IndexPath(row: index, section: 0), animated: false, scrollPosition: .none)
            onReplyPress()
        default:
            break
        }
        self.message = nil
    }
    
    func setupToolbar(){
        self.navigationController?.navigationBar.addSubview(self.topToolbar)
        let margins = self.navigationController!.navigationBar.layoutMarginsGuide
        self.topToolbar.leadingAnchor.constraint(equalTo: margins.leadingAnchor, constant: -8.0).isActive = true
        self.topToolbar.trailingAnchor.constraint(equalTo: margins.trailingAnchor, constant: 8.0).isActive = true
        self.topToolbar.bottomAnchor.constraint(equalTo: margins.bottomAnchor, constant: 8.0).isActive = true
        self.navigationController?.navigationBar.bringSubview(toFront: self.topToolbar)
        self.topToolbar.isHidden = true
        
        let cancelButton = UIButton(type: .custom)
        cancelButton.frame = CGRect(x: 0, y: 0, width: 31, height: 31)
        cancelButton.setImage(#imageLiteral(resourceName: "menu-back"), for: .normal)
        cancelButton.layer.backgroundColor = UIColor(red:0.31, green:0.32, blue:0.36, alpha:1.0).cgColor
        cancelButton.tintColor = UIColor(red:0.56, green:0.56, blue:0.58, alpha:1.0)
        cancelButton.layer.cornerRadius = 15.5
        let cancelBarButton = UIBarButtonItem(customView: cancelButton)
        self.navigationItem.leftBarButtonItem = cancelBarButton
    }
    
    func setupMoreOptionsViews(){
        emailsTableView.sectionHeaderHeight = UITableViewAutomaticDimension;
        emailsTableView.estimatedSectionHeaderHeight = ESTIMATED_SECTION_HEADER_HEIGHT;
        if emailData.selectedLabel == SystemLabel.trash.id || emailData.selectedLabel == SystemLabel.spam.id {
            moreOptionsContainerView.deleteButton.setTitle(String.localize("DELETE_PERMANENTLY"), for: .normal)
        }
        moreOptionsContainerView.delegate = self
    }
    
    func registerCellNibs(){
        let headerNib = UINib(nibName: "EmailTableHeaderView", bundle: nil)
        self.emailsTableView.register(headerNib, forHeaderFooterViewReuseIdentifier: "emailTableHeaderView")
        let footerNib = UINib(nibName: "EmailTableFooterView", bundle: nil)
        self.emailsTableView.register(footerNib, forHeaderFooterViewReuseIdentifier: "emailTableFooterView")
        for email in self.emailData.emails {
            let nib = UINib(nibName: "EmailDetailTableCell", bundle: nil)
            self.emailsTableView.register(nib, forCellReuseIdentifier: "emailDetail\(email.key)")
        }
    }
    
    func displayMarkIcon(asRead: Bool){
        topToolbar.swapMarkTo(unread: !asRead)
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        let email = emailData.emails[indexPath.row]
        return emailData.getState(email.key).cellHeight < ESTIMATED_ROW_HEIGHT ? ESTIMATED_ROW_HEIGHT : emailData.getState(email.key).cellHeight
    }
}

extension EmailDetailViewController: UITableViewDelegate, UITableViewDataSource{

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let email = emailData.emails[indexPath.row]
        let cell = reuseOrCreateCell(identifier: "emailDetail\(email.key)") as! EmailTableViewCell
        cell.setContent(email, emailBody: self.emailData.bodies[email.key] ?? "", state: emailData.getState(email.key), myEmail: emailData.accountEmail)
        cell.delegate = self
        target = cell.moreOptionsContainerView
        if(isGroupable()){
            cell.counterLabelUp.text = "\(self.emailData.emails.count - 2)"
            cell.counterLabelDown.text = "\(self.emailData.emails.count - 2)"
            if(email == emailData.emails.first){
                cell.upView.isHidden = true
                cell.bottomView.isHidden = false
                cell.isHidden = false
                return cell
            }else if(email == emailData.emails.last){
                cell.upView.isHidden = false
                cell.bottomView.isHidden = true
                cell.isHidden = false
                return cell
            }else{
                cell.isHidden = true
                return self.tableView(tableView, cellForRowAt: IndexPath(row: indexPath.row + 1, section: 0))
            }
        }else{
            cell.upView.isHidden = true
            cell.bottomView.isHidden = true
            cell.counterLabelUp.isHidden = true
            cell.counterLabelDown.isHidden = true
            cell.isHidden = false
            return cell
        }
    }
    
    func reuseOrCreateCell(identifier: String) -> UITableViewCell {
        guard let cell = emailsTableView.dequeueReusableCell(withIdentifier: identifier) else {
            let nib = UINib(nibName: "EmailDetailTableCell", bundle: nil)
            emailsTableView.register(nib, forCellReuseIdentifier: identifier)
            return reuseOrCreateCell(identifier: identifier)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if(isGroupable()){
            return 2
        }else{
            return emailData.emails.count
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard myHeaderView == nil else {
            return myHeaderView
        }
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "emailTableHeaderView") as! EmailDetailHeaderCell
        headerView.addLabels(emailData.labels)
        headerView.setSubject(emailData.subject)
        headerView.onStarPressed = { [weak self] in
            self?.onStarPressed()
        }
        myHeaderView = headerView
        return myHeaderView
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "emailTableFooterView") as! EmailDetailFooterCell
        footerView.delegate = self
        return footerView
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 78.0
    }
}

extension EmailDetailViewController: EmailTableViewCellDelegate {
    
    func tableViewExpandViews() {
        isExpanded = true
        emailsTableView.reloadData()
    }
    
    func tableViewCellDidTapEmail(email: String) {
        var contact: Contact
        if let existingContact = DBManager.getContact(email) {
            contact = existingContact
        } else {
            contact = Contact()
            contact.email = email
            contact.displayName = String(email.split(separator: "@").first!)
            DBManager.store([contact])
        }
        presentComposer(contactsTo: [contact])
    }
    
    func tableViewCellDidTapLink(url: String) {
        let svc = SFSafariViewController(url: URL(string: url)!)
        self.present(svc, animated: true, completion: nil)
    }
    
    func tableViewCellDidChangeHeight(_ height: CGFloat, email: Email) {
        emailData.setState(email.key, cellHeight: height)
        self.emailsTableView.reloadData()
    }
    
    func tableViewCellDidLoadContent(_ cell: EmailTableViewCell, email: Email) {
        self.emailsTableView.reloadData()
    }
    
    func tableViewCellDidTap(_ cell: EmailTableViewCell) {
        guard let indexPath = self.emailsTableView.indexPath(for: cell) else {
            return
        }
        let email = emailData.emails[indexPath.row]
        emailData.setState(email.key, isExpanded: !emailData.getState(email.key).isExpanded)
        emailsTableView.reloadData()
    }
    
    func tableViewCellDidTapAttachment(file: File) {
        PHPhotoLibrary.requestAuthorization({ (status) in
            DispatchQueue.main.async { [weak self] in
                guard let weakSelf = self else {
                    return
                }
                switch status {
                case .authorized:
                    if(!file.fileKey.isEmpty){
                        let keys = File.getKeyAndIv(key: file.fileKey)
                        weakSelf.fileManager.setEncryption(id: file.emailId, key: keys.0, iv: keys.1)
                    }
                    if let attachmentCell = weakSelf.getCellFromFile(file) {
                        attachmentCell.markImageView.isHidden = true
                        attachmentCell.progressView.isHidden = false
                        attachmentCell.progressView.setProgress(0, animated: false)
                    }
                    weakSelf.fileManager.registerFile(file: file)
                    break
                default:
                    weakSelf.showAlert(String.localize("ACCESS_DENIED"), message: String.localize("NEED_ENABLE_ACCESS"), style: .alert)
                    break
                }
            }
        })
    }
    
    func tableViewCellDidTapIcon(_ cell: EmailTableViewCell, _ sender: UIView, _ iconType: EmailTableViewCell.IconType) {
        switch(iconType){
        case .contacts:
            handleContactsTap(cell, sender)
        case .options:
            handleOptionsTap(cell, sender)
        case .edit:
            handleEditTap(cell, sender)
        }
    }
    
    func handleEditTap(_ cell: EmailTableViewCell, _ sender: UIView){
        guard let indexPath = emailsTableView.indexPath(for: cell) else {
            return
        }
        let email = emailData.emails[indexPath.row]
        let contactsTo = Array(email.getContacts(type: .to))
        let contactsCc = Array(email.getContacts(type: .cc))
        presentComposer(email: email, contactsTo: contactsTo, contactsCc: contactsCc, subject: email.subject, content: self.emailData.bodies[email.key] ?? "")
    }
    
    func handleContactsTap(_ cell: EmailTableViewCell, _ sender: UIView){
        guard let indexPath = emailsTableView.indexPath(for: cell) else {
            return
        }
        let email = emailData.emails[indexPath.row]
        let contactsPopover = ContactsDetailUIPopover()
        contactsPopover.email = email
        presentPopover(contactsPopover, sender, height: min(CGFloat(CONTACTS_BASE_HEIGHT + email.emailContacts.count * CONTACTS_ROW_HEIGHT), CONTACTS_MAX_HEIGHT))
    }
    
    func presentPopover(_ popover: UIViewController, _ sender: UIView, height: CGFloat){
        popover.preferredContentSize = CGSize(width: self.view.frame.size.width - 20, height: height)
        popover.popoverPresentationController?.sourceView = sender
        popover.popoverPresentationController?.sourceRect = CGRect(x: 0, y: 0, width: sender.frame.size.width/1.0001, height: sender.frame.size.height)
        popover.popoverPresentationController?.permittedArrowDirections = [.up, .down]
        popover.popoverPresentationController?.backgroundColor = theme.overallBackground
        self.present(popover, animated: true, completion: nil)
    }
    
    func handleOptionsTap(_ cell: EmailTableViewCell, _ sender: UIView){
        guard let indexPath = emailsTableView.indexPath(for: cell) else {
            return
        }
        moreOptionsContainerView.spamButton.setTitle(emailData.selectedLabel == SystemLabel.spam.id ? String.localize("REMOVE_SPAM") : String.localize("MARK_SPAM"), for: .normal)
        emailsTableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        let email = emailData.emails[indexPath.row]
        moreOptionsContainerView.showRetry((email.status == .fail || email.status == .sending) ? true : false)
        moreOptionsContainerView.showUnsend(email.secure && email.status != .unsent && email.status != .none && email.status != .sending)
        moreOptionsContainerView.showSourceButton(!email.boundary.isEmpty)
        toggleMoreOptionsView()
    }
    
    func deselectSelectedRow(){
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            return
        }
        emailsTableView.deselectRow(at: indexPath, animated: false)
    }
    
    @objc func toggleMoreOptionsView(){
        self.coachMarksController.stop(immediately: true)
        guard moreOptionsContainerView.isHidden else {
            moreOptionsContainerView.closeMoreOptions()
            deselectSelectedRow()
            return
        }
        moreOptionsContainerView.showMoreOptions()
    }
    
    @objc func toggleGeneralOptionsView(){
        guard generalOptionsContainerView.isHidden else {
            generalOptionsContainerView.closeMoreOptions()
            return
        }
        generalOptionsContainerView.showMoreOptions()
        let title = (emailData.emails.count) > 1 ? String.localize("PRINT_ALL") : String.localize("PRINT")
        generalOptionsContainerView.printallButton.setTitle(title, for: .normal)
    }
}

extension EmailDetailViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = self.navigationController else {
            return false
        }
        if(nav.viewControllers.count > 1){
            return true
        }
        return false
    }
}

extension EmailDetailViewController: EmailDetailFooterDelegate {
    
    func presentComposer(email: Email, contactsTo: [Contact], contactsCc: [Contact], subject: String, content: String, attachments: [File]? = nil){
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let navComposeVC = storyboard.instantiateViewController(withIdentifier: "NavigationComposeViewController") as! UINavigationController
        let snackVC = SnackbarController(rootViewController: navComposeVC)
        let composerVC = navComposeVC.viewControllers.first as! ComposeViewController
        let composerData = ComposerData()
        composerData.initToContacts.append(contentsOf: contactsTo)
        composerData.initCcContacts.append(contentsOf: contactsCc)
        composerData.initSubject = subject
        composerData.initContent = content
        composerData.threadId = emailData.threadId
        composerData.emailDraft = email.isDraft ? email : nil
        if(email.isDraft){
            for file in email.files {
                file.requestStatus = .finish
                composerVC.fileManager.registeredFiles.append(file)
            }
        } else if let files = attachments {
            for file in files {
                let newFile = file.duplicate()
                newFile.requestStatus = .finish
                composerVC.fileManager.registeredFiles.append(newFile)
            }
        }
        composerVC.delegate = self
        composerVC.composerData = composerData
        self.navigationController?.childViewControllers.last!.present(snackVC, animated: true, completion: nil)
    }
    
    func presentComposer(contactsTo: [Contact]){
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let navComposeVC = storyboard.instantiateViewController(withIdentifier: "NavigationComposeViewController") as! UINavigationController
        let snackVC = SnackbarController(rootViewController: navComposeVC)
        let composerVC = navComposeVC.viewControllers.first as! ComposeViewController
        let composerData = ComposerData()
        composerData.initToContacts.append(contentsOf: contactsTo)
        composerVC.delegate = self
        composerVC.composerData = composerData
        self.navigationController?.childViewControllers.last!.present(snackVC, animated: true, completion: nil)
    }
    
    func onFooterReplyPress() {
        guard let lastIndex = emailData.emails.lastIndex(where: {!$0.isDraft}) else {
            return
        }
        emailsTableView.selectRow(at: IndexPath(row: lastIndex, section: 0), animated: false, scrollPosition: .none)
        onReplyPress()
    }
    
    func onFooterReplyAllPress() {
        guard let lastIndex = emailData.emails.lastIndex(where: {!$0.isDraft}) else {
            return
        }
        emailsTableView.selectRow(at: IndexPath(row: lastIndex, section: 0), animated: false, scrollPosition: .none)
        onReplyAllPress()
    }
    
    func onFooterForwardPress() {
        guard let lastIndex = emailData.emails.lastIndex(where: {!$0.isDraft}) else {
            return
        }
        emailsTableView.selectRow(at: IndexPath(row: lastIndex, section: 0), animated: false, scrollPosition: .none)
        onForwardPress()
    }
}

extension EmailDetailViewController: NavigationToolbarDelegate {
    func onBackPress() {
        self.emailData.observerToken?.invalidate()
        self.emailData.observerToken = nil
        self.navigationController?.popViewController(animated: true)
    }
    
    func onMoveThreads() {
        handleMoveTo()
    }
    
    func onTrashThreads() {
        guard emailData.selectedLabel == SystemLabel.trash.id || emailData.selectedLabel == SystemLabel.spam.id || emailData.selectedLabel == SystemLabel.draft.id else {
            self.setLabels(added: [SystemLabel.trash.id], removed: [], forceRemove: true)
            return
        }
        let popover = GenericDualAnswerUIPopover()
        popover.initialTitle = String.localize("DELETE_THREADS")
        popover.initialMessage = String.localize("THESE_DELETED_PERMANENTLY")
        popover.leftOption = String.localize("CANCEL")
        popover.rightOption = String.localize("OK")
        popover.onResponse = { [weak self] accept in
            guard accept,
                let weakSelf = self else {
                    return
            }
            DBManager.delete(Array(weakSelf.emailData.emails))
            weakSelf.mailboxData.removeSelectedRow = true
            weakSelf.navigationController?.popViewController(animated: true)
            
            let eventData = EventData.Peer.ThreadDeleted(threadIds: [weakSelf.emailData.threadId])
            DBManager.createQueueItem(params: ["cmd": Event.Peer.threadsDeleted.rawValue, "params": eventData.asDictionary()])
        }
        self.presentPopover(popover: popover, height: 200)
    }
    
    func onMarkThreads() {
        let unread = self.mailboxData.unreadMails <= 0
        for email in self.emailData.emails {
            DBManager.updateEmail(email, unread: true)
        }
        self.navigationController?.popViewController(animated: true)
        
        let params = ["cmd": Event.Peer.threadsUnread.rawValue,
                      "params": [
                        "unread": unread ? 1 : 0,
                        "threadIds": [emailData.threadId]
            ]] as [String : Any]
        DBManager.createQueueItem(params: params)
    }
    
    func onMoreOptions() {
        toggleGeneralOptionsView()
    }
    
    func archiveThreads(){
        toggleGeneralOptionsView()
        setLabels(added: [], removed: [SystemLabel.inbox.id])
    }
    
    func restoreThreads(){
        toggleGeneralOptionsView()
        setLabels(added: [], removed: [emailData.selectedLabel])
    }
}

extension EmailDetailViewController: DetailMoreOptionsViewDelegate {
    func onRetryPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            self.toggleMoreOptionsView()
            return
        }
        let email = emailData.emails[indexPath.row]
        DBManager.addRemoveLabelsFromEmail(email, addedLabelIds: [SystemLabel.sent.id], removedLabelIds: [SystemLabel.draft.id])
        DBManager.updateEmail(email, status: Email.Status.sending.rawValue)
        sendMail(email: email, emailBody: self.emailData.bodies[email.key] ?? "", password: nil)
    }
    
    func onReplyPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            moreOptionsContainerView.closeMoreOptions()
            return
        }
        moreOptionsContainerView.closeMoreOptions()
        deselectSelectedRow()
        let email = emailData.emails[indexPath.row]
        let fromContact = email.fromContact
        let contactsTo = (fromContact.email == emailData.accountEmail) ? Array(email.getContacts(type: .to)) : [fromContact]
        let subject = "\(email.subject.lowercased().starts(with: "re:") ? "" : "Re: ")\(email.subject)"
        let contact = ContactUtils.checkIfFromHasName(email.fromAddress) ? email.fromAddress : "\(email.fromContact.displayName) &#60;\(email.fromContact.email)&#62;"
        let content = ("<br><br><div class=\"criptext_quote\">\(String.localize("ON_REPLY")) \(email.completeDate), \(contact) wrote:<br><blockquote class=\"gmail_quote\" style=\"margin:0 0 0 .8ex;border-left:1px #ccc solid;padding-left:1ex\">\(self.emailData.bodies[email.key] ?? "")</blockquote></div>")
        presentComposer(email: email, contactsTo: contactsTo, contactsCc: [], subject: subject, content: content)
    }
    
    func onReplyAllPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            moreOptionsContainerView.closeMoreOptions()
            return
        }
        moreOptionsContainerView.closeMoreOptions()
        deselectSelectedRow()
        let email = emailData.emails[indexPath.row]
        var contactsTo = [Contact]()
        var contactsCc = [Contact]()
        let myEmail = emailData.accountEmail
        contactsTo.append(contentsOf: email.getContacts(type: .from, notEqual: myEmail))
        contactsTo.append(contentsOf: email.getContacts(type: .to, notEqual: myEmail))
        contactsCc.append(contentsOf: email.getContacts(type: .cc, notEqual: myEmail))
        let subject = "\(email.subject.lowercased().starts(with: "re:") ? "" : "Re: ")\(email.subject)"
        let contact = ContactUtils.checkIfFromHasName(email.fromAddress) ? email.fromAddress : "\(email.fromContact.displayName) &#60;\(email.fromContact.email)&#62;"
        let content = ("<br><br><div class=\"criptext_quote\">\(String.localize("ON_REPLY")) \(email.completeDate), \(contact) wrote:<br><blockquote class=\"gmail_quote\" style=\"margin:0 0 0 .8ex;border-left:1px #ccc solid;padding-left:1ex\">\(self.emailData.bodies[email.key] ?? "")</blockquote></div>")
        presentComposer(email: email, contactsTo: contactsTo, contactsCc: contactsCc, subject: subject, content: content)
    }
    
    func onForwardPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            moreOptionsContainerView.closeMoreOptions()
            return
        }
        moreOptionsContainerView.closeMoreOptions()
        deselectSelectedRow()
        let email = emailData.emails[indexPath.row]
        let subject = "\(email.subject.lowercased().starts(with: "fw:") || email.subject.lowercased().starts(with: "fwd:") ? "" : "Fw: ")\(email.subject)"
        let contact = ContactUtils.checkIfFromHasName(email.fromAddress) ? email.fromAddress : "<b>\(email.fromContact.displayName) &#60;\(email.fromContact.email)&#62;"
        let content = ("<br><br><div class=\"criptext_quote\"><span>---------- \(String.localize("FORWARD_MAIL")) ---------</span><br><span>\(String.localize("FROM")): ]\(contact)</span><br><span>\(String.localize("DATE")): \(email.completeDate)</span><br><span>\(String.localize("SUBJECT")): \(email.subject)</span><br><br>\(self.emailData.bodies[email.key] ?? "")</div>")
        presentComposer(email: email, contactsTo: [], contactsCc: [], subject: subject, content: content, attachments: email.getFiles())
    }
    
    func onDeletePress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            self.toggleMoreOptionsView()
            return
        }
        self.toggleMoreOptionsView()
        let email = emailData.emails[indexPath.row]
        guard emailData.selectedLabel == SystemLabel.trash.id || emailData.selectedLabel == SystemLabel.spam.id || emailData.selectedLabel == SystemLabel.draft.id else {
            self.moveSingleEmailToTrash(email, indexPath: indexPath)
            return
        }
        let popover = GenericDualAnswerUIPopover()
        popover.initialTitle = String.localize("DELETE_EMAIL")
        popover.initialMessage = String.localize("EMAIL_DELETE_PERMANENTLY")
        popover.leftOption = String.localize("CANCEL")
        popover.rightOption = String.localize("Ok")
        popover.onResponse = { [weak self] accept in
            guard accept,
                let weakSelf = self else {
                    return
            }
            weakSelf.deleteSingleEmail(email, indexPath: indexPath)
        }
        self.presentPopover(popover: popover, height: 170)
    }
    
    func deleteSingleEmail(_ email: Email, indexPath: IndexPath){
        let triggerEvent = email.canTriggerEvent
        let emailKey = email.key
        DBManager.delete(email)
        if (triggerEvent) {
            let eventData = EventData.Peer.EmailDeleted(metadataKeys: [emailKey])
            DBManager.createQueueItem(params: ["cmd": Event.Peer.emailsDeleted.rawValue, "params": eventData.asDictionary()])
        }
    }
    
    func moveSingleEmailToTrash(_ email: Email, indexPath: IndexPath){
        let triggerEvent = email.canTriggerEvent
        let changedLabels = getLabelNames(added: [SystemLabel.trash.id], removed: [])
        let emailKey = email.key
        DBManager.addRemoveLabelsFromEmail(email, addedLabelIds: [SystemLabel.trash.id], removedLabelIds: [])
        if (triggerEvent) {
            let eventData = EventData.Peer.EmailLabels(metadataKeys: [emailKey], labelsAdded: changedLabels.0, labelsRemoved: changedLabels.1)
            DBManager.createQueueItem(params: ["cmd": Event.Peer.emailsLabels.rawValue, "params": eventData.asDictionary()])
        }
    }
    
    func onMarkPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            self.toggleMoreOptionsView()
            return
        }
        let thresholdDate = emailData.emails[indexPath.row].date
        var emailKeys = [Int]()
        for email in emailData.emails {
            guard email.date >= thresholdDate else {
                continue
            }
            DBManager.updateEmail(email, unread: true)
            guard email.canTriggerEvent else {
                continue
            }
            emailKeys.append(email.key)
        }
        if !emailKeys.isEmpty {
            let params = ["cmd": Event.Peer.emailsUnread.rawValue,
                          "params": [
                            "unread": 1,
                            "metadataKeys": emailKeys
                ]] as [String : Any]
            self.navigationController?.popViewController(animated: true)
            DBManager.createQueueItem(params: params)
        }
        self.navigationController?.popViewController(animated: true)
    }
    
    func onSpamPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            self.toggleMoreOptionsView()
            return
        }
        self.toggleMoreOptionsView()
        let isSpam = emailData.selectedLabel == SystemLabel.spam.id
        let isTrash = emailData.selectedLabel == SystemLabel.trash.id
        let removeLabel = isSpam ? [SystemLabel.spam.id] : isTrash ? [SystemLabel.trash.id] : []
        let addLabel = isSpam ? [] : [SystemLabel.spam.id]
        let email = emailData.emails[indexPath.row]
        let emailKey = email.key
        
        let changedLabels = getLabelNames(added: addLabel, removed: removeLabel)
        DBManager.addRemoveLabelsFromEmail(email, addedLabelIds: addLabel, removedLabelIds: removeLabel)
        let eventData = EventData.Peer.EmailLabels(metadataKeys: [emailKey], labelsAdded: changedLabels.0, labelsRemoved: changedLabels.1)
        DBManager.createQueueItem(params: ["cmd": Event.Peer.emailsLabels.rawValue, "params": eventData.asDictionary()])
    }
    
    func onUnsendPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow,
            let cell = emailsTableView.cellForRow(at: indexPath) as? EmailTableViewCell else {
            self.toggleMoreOptionsView()
            return
        }
        let email = emailData.emails[indexPath.row]
        self.toggleMoreOptionsView()
        guard email.status != .unsent && email.isSent else {
            return
        }
        emailData.setState(email.key, isUnsending: true)
        emailsTableView.reloadData()
        let recipients = getEmailRecipients(contacts: email.getContacts())
        APIManager.unsendEmail(key: email.key, recipients: recipients, account: myAccount) { [weak self] (responseData) in
            guard let weakSelf = self else {
                return
            }
            weakSelf.emailData.setState(email.key, isUnsending: false)
            if case .Unauthorized = responseData {
                weakSelf.logout(account: weakSelf.myAccount)
                return
            }
            if case .Forbidden = responseData {
                weakSelf.presentPasswordPopover(myAccount: weakSelf.myAccount)
                return
            }
            if case .Conflicts = responseData {
                weakSelf.showAlert(String.localize("UNSEND_FAILED"), message: String.localize("UNSEND_EXPIRED"), style: .alert)
                weakSelf.emailsTableView.reloadData()
                return
            }
            guard case .Success = responseData else {
                weakSelf.showAlert(String.localize("UNSEND_FAILED"), message: String.localize("UNABLE_UNSEND"), style: .alert)
                weakSelf.emailsTableView.reloadData()
                return
            }
            cell.isLoaded = false
            FileUtils.deleteDirectoryFromEmail(account: weakSelf.myAccount, metadataKey: "\(email.key)")
            DBManager.unsendEmail(email)
        }
    }

    func onPrintPress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            return
        }
        let email = emailData.emails[indexPath.row]
        let subject = "\(email.subject.lowercased().starts(with: "fw:") || email.subject.lowercased().starts(with: "fwd:") ? "" : "Fw: ")\(email.subject)"
        let image = UIImage(named: "footer_beta")
        let imageData:Data =  UIImagePNGRepresentation(image!)!
        let contact = ContactUtils.checkIfFromHasName(email.fromAddress) ? email.fromAddress : "\(email.fromContact.displayName) &#60;\(email.fromContact.email)&#62;"
        let html = Constants.singleEmail(image: imageData.base64EncodedString(), subject: subject, contact: SharedUtils.replaceContactToStringChar(text: contact), completeDate: email.completeDate, contacts: SharedUtils.replaceContactToStringChar(text: email.getFullContacts()), content: self.emailData.bodies[email.key] ?? "")
        webView.frame = self.view.bounds
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    func getEmailRecipients(contacts: [Contact]) -> [String]{
        return contacts.reduce([String](), { (result, contact) -> [String] in
            guard contact.email != emailData.accountEmail else {
                return result
            }
            return result + [contact.email]
        })
    }
    
    func onOverlayPress() {
        self.toggleMoreOptionsView()
    }
    
    func onShowSourcePress() {
        guard let indexPath = emailsTableView.indexPathForSelectedRow else {
            moreOptionsContainerView.closeMoreOptions()
            return
        }
        moreOptionsContainerView.closeMoreOptions()
        deselectSelectedRow()
        let email = emailData.emails[indexPath.row]
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let viewController = storyboard.instantiateViewController(withIdentifier: "EmailSourceViewController") as! EmailSourceViewController
        viewController.email = email
        viewController.myAccount = self.myAccount
        self.present(viewController, animated: true, completion: nil)
    }
}

extension EmailDetailViewController: UIWebViewDelegate {
    func webViewDidStartLoad(_ webView: UIWebView) {
    }
    
    func webViewDidFinishLoad(_ webView: UIWebView) {
        let printer = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary:nil)
        
        printInfo.outputType = UIPrintInfoOutputType.general
        printInfo.jobName = emailData.subject
        
        printer.showsPaperSelectionForLoadedPapers = true
        printer.printInfo = printInfo
        printer.printFormatter = webView.viewPrintFormatter()
        
        printer.present(animated: true, completionHandler: nil)
    }
    
    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
    }
}

extension EmailDetailViewController : GeneralMoreOptionsViewDelegate {
    func onDismissPress() {
        toggleGeneralOptionsView()
    }
    
    func onMoveToPress() {
        handleMoveTo()
    }
    
    func onAddLabesPress() {
        handleAddLabels()
    }
    
    func onRestorePress() {
        self.restoreThreads()
    }
    
    func onArchivePress() {
        self.archiveThreads()
    }

    func onPrintAllPress() {
        let emails = self.emailData.emails
        guard let email = emails?.first else{
            return
        }
        let subject = "\(email.subject.lowercased().starts(with: "fw:") || email.subject.lowercased().starts(with: "fwd:") ? "" : "Fw: ")\(email.subject)"
        var body = String()
        for mail in emails!{
            let contact = mail.fromAddress.isEmpty ? "\(mail.fromContact.displayName)</b> &lt;\(mail.fromContact.email)&gt;" : mail.fromAddress
            body = "\(body) \(Constants.bodyEmail(contact: SharedUtils.replaceContactToStringChar(text: contact), completeDate: mail.completeDate, contacts: SharedUtils.replaceContactToStringChar(text: mail.getFullContacts()), content: self.emailData.bodies[mail.key] ?? "")) <hr>"
        }
        let image = UIImage(named: "footer_beta")
        let imageData:Data =  UIImagePNGRepresentation(image!)!
        let message = (emailData.emails.count) > 1 ? "\((emails?.count)!) \(String.localize("MESSAGES"))" : "1 \(String.localize("MESSAGE"))"
        let html = Constants.threadEmail(image: imageData.base64EncodedString(), subject: subject, body: body, messages: message)
        webView.frame = self.view.bounds
        webView.loadHTMLString(html, baseURL: nil)
    }
}

extension EmailDetailViewController : LabelsUIPopoverDelegate{
    
    func handleAddLabels(){
        let labelsPopover = LabelsUIPopover.instantiate(type: .addLabels, selectedLabel: emailData.selectedLabel)
        for label in emailData.labels {
            labelsPopover.selectedLabels[label.id] = label
        }
        presentPopover(labelsPopover, height: Constants.basePopoverHeight + labelsPopover.labels.count * Constants.labelPopoverHeight)
    }
    
    func handleMoveTo(){
        let labelsPopover = LabelsUIPopover.instantiate(type: .moveTo, selectedLabel: emailData.selectedLabel)
        presentPopover(labelsPopover, height: Constants.basePopoverHeight + labelsPopover.labels.count * Constants.labelPopoverHeight)
    }
    
    func presentPopover(_ popover: LabelsUIPopover, height: Int){
        popover.delegate = self
        popover.preparePopover(rootView: self, height: height)
        self.present(popover, animated: true){ [weak self] in
            guard let weakSelf = self else {
                return
            }
            weakSelf.generalOptionsContainerView.closeMoreOptions()
            weakSelf.view.layoutIfNeeded()
        }
    }
    
    func setLabels(added: [Int], removed: [Int]) {
        setLabels(added: added, removed: removed, forceRemove: false)
    }
    
    func moveTo(labelId: Int) {
        let removeLabels = labelId == SystemLabel.all.id
            ? [SystemLabel.inbox.id]
            : emailData.selectedLabel == SystemLabel.trash.id && labelId == SystemLabel.spam.id ? [SystemLabel.trash.id] : []
        let addLabels = labelId == SystemLabel.all.id
            ? []
            : [labelId]
        setLabels(added: addLabels, removed: removeLabels, forceRemove: labelId == SystemLabel.trash.id || labelId == SystemLabel.spam.id)
    }
    
    func setLabels(added: [Int], removed: [Int], forceRemove: Bool){
        let changedLabels = getLabelNames(added: added, removed: removed)
        DBManager.addRemoveLabelsForThreads(self.emailData.threadId, addedLabelIds: added, removedLabelIds: removed, currentLabel: self.emailData.selectedLabel)
        self.emailData.rebuildLabels()
        if(forceRemove){
            self.mailboxData.removeSelectedRow = true
            self.navigationController?.popViewController(animated: true)
        } else {
            self.myHeaderView = nil
            self.emailsTableView.reloadData()
        }
        
        let eventData = EventData.Peer.ThreadLabels(threadIds: [emailData.threadId], labelsAdded: changedLabels.0, labelsRemoved: changedLabels.1)
        DBManager.createQueueItem(params: ["params": eventData.asDictionary(), "cmd": Event.Peer.threadsLabels.rawValue])
    }
    
    func getLabelNames(added: [Int], removed: [Int]) -> ([String], [String]){
        var addedNames = [String]()
        var removedNames = [String]()
        for id in added {
            guard let label = DBManager.getLabel(id) else {
                continue
            }
            addedNames.append(label.text)
        }
        for id in removed {
            guard let label = DBManager.getLabel(id) else {
                continue
            }
            removedNames.append(label.text)
        }
        return (addedNames, removedNames)
    }
}

extension EmailDetailViewController : CriptextFileDelegate, UIDocumentInteractionControllerDelegate {
    func fileError(message: String) {
        let alertPopover = GenericAlertUIPopover()
        alertPopover.myTitle = String.localize("FILE_ERROR")
        alertPopover.myMessage = message
        self.presentPopover(popover: alertPopover, height: 205)
    }
    
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        return self
    }
    
    func uploadProgressUpdate(file: File, progress: Int) {
        guard let attachmentCell = getCellFromFile(file) else {
            return
        }
        attachmentCell.markImageView.isHidden = true
        attachmentCell.progressView.isHidden = false
        attachmentCell.progressView.setProgress(Float(progress)/100.0, animated: true)
    }
    
    func finishRequest(file: File, success: Bool) {
        if(success){
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsURL.appendingPathComponent(file.name)
            let viewer = UIDocumentInteractionController(url: fileURL)
            viewer.delegate = self
            viewer.presentPreview(animated: true)
        }
        guard let attachmentCell = getCellFromFile(file) else {
            return
        }
        attachmentCell.setMarkIcon(success: success)
    }
    
    func getCellFromFile(_ file: File) -> AttachmentTableCell? {
        guard let emailIndex = emailData.emails.index(where: {$0.key == file.emailId}),
            let index = emailData.emails[emailIndex].files.index(where: {$0.token == file.token}),
            let emailCell = self.emailsTableView.cellForRow(at: IndexPath(row: emailIndex, section: 0)) as? EmailTableViewCell,
            let attachmentCell = emailCell.attachmentsTableView.cellForRow(at: IndexPath(row: index, section: 0)) as? AttachmentTableCell else {
                return nil
        }
        return attachmentCell
    }
    
}

extension EmailDetailViewController: ComposerSendMailDelegate {
    func newDraft(draft: Email) {
        
    }
    
    func deleteDraft(draftId: Int) {
    }
    
    func sendMail(email: Email, emailBody: String, password: String?) {
        guard let inboxViewController = navigationController?.viewControllers.first as? InboxViewController else {
            return
        }
        inboxViewController.sendMail(email: email, emailBody: emailBody, password: password)
    }
}

extension EmailDetailViewController {
    func onStarPressed() {
        let threadIsStarred = emailData.labels.contains(where: {$0.id == SystemLabel.starred.id})
        let addedLabels = threadIsStarred ? [] : [SystemLabel.starred.id]
        let removedLabels = threadIsStarred ? [SystemLabel.starred.id] : []
        setLabels(added: addedLabels, removed: removedLabels)
    }
}

extension EmailDetailViewController: CoachMarksControllerDataSource, CoachMarksControllerDelegate {
    
    func coachMarksController(_ coachMarksController: CoachMarksController, coachMarkViewsAt index: Int, madeFrom coachMark: CoachMark) -> (bodyView: CoachMarkBodyView, arrowView: CoachMarkArrowView?) {
        let hintView = HintUIView()
        hintView.messageLabel.text = String.localize("GUIDE_UNSEND")
        hintView.rightConstraint.constant = 50
        hintView.topCenterConstraint.constant = -25
        
        return (bodyView: hintView, arrowView: nil)
    }
    
    func coachMarksController(_ coachMarksController: CoachMarksController, coachMarkAt index: Int) -> CoachMark {
        var coachMark = coachMarksController.helper.makeCoachMark(for: target) { frame in
            return UIBezierPath(ovalIn: frame.insetBy(dx: -4, dy: -4))
        }
        coachMark.allowTouchInsideCutoutPath = true
        return coachMark
    }
    
    func numberOfCoachMarks(for coachMarksController: CoachMarksController) -> Int {
        return 1
    }
}

extension EmailDetailViewController: LinkDeviceDelegate {
    func onAcceptLinkDevice(linkData: LinkData) {
        guard linkData.version == Env.linkVersion else {
            let popover = GenericAlertUIPopover()
            popover.myTitle = String.localize("VERSION_TITLE")
            popover.myMessage = String.localize("VERSION_MISMATCH")
            self.presentPopover(popover: popover, height: 220)
            return
        }
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let linkDeviceVC = storyboard.instantiateViewController(withIdentifier: "connectUploadViewController") as! ConnectUploadViewController
        linkDeviceVC.linkData = linkData
        linkDeviceVC.myAccount = myAccount
        self.present(linkDeviceVC, animated: true, completion: nil)
    }
    func onCancelLinkDevice(linkData: LinkData) {
        if case .sync = linkData.kind {
            APIManager.syncDeny(randomId: linkData.randomId, account: myAccount, completion: {_ in })
        } else {
            APIManager.linkDeny(randomId: linkData.randomId, account: myAccount, completion: {_ in })
        }
    }
}
