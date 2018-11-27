//
//  ViewController.swift
//  aem-manager-osx
//
//  Created by Peter Mannel-Wiedemann on 27.11.15.
//
//

import Cocoa

import os.log

class ViewController: NSViewController {
    
    // MARK: properties
    @IBOutlet weak var table: NSTableView!
    
    
    var instances = AEMInstance.loadAEMInstances()
    weak var selectedInstance: AEMInstance?
    
    var guiarray:[NSWindowController] = []
    var statusBarItems: [StatusBarItem] = []
    
    var timer = Timer()
    var timer2 = Timer()
    var tagName: String = ""
    
    func backgroundThread(_ delay: Double = 0.0, background: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.background).async {
            if(background != nil){ background!(); }
            
            let popTime = DispatchTime.now() + Double(Int64(delay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
            DispatchQueue.main.asyncAfter(deadline: popTime) {
                if(completion != nil){ completion!(); }
            }
        }
    }
    
    override func viewDidAppear() {
        checkVersion()
        
        timer = Timer.scheduledTimer(timeInterval: 4.0, target: self, selector: #selector(ViewController.checkStatus), userInfo: nil, repeats: true)
        
        timer2 = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(ViewController.checkVersion), userInfo: nil, repeats: false)
        
    }
    
    @objc func checkStatus(){
        for instance in instances {
            AemActions.checkBundleState(instance)
        }
        
        table.reloadData()
        
        statusBarItems.forEach{
            item in item.updateStatus()
        }
    }
    
    @IBAction func checkVersionUpdate(_ sender: NSMenuItem){
        checkVersion()
        
    }
    
    @objc func checkVersion(){
        let nsObject: AnyObject? = Bundle.main.infoDictionary!["CFBundleShortVersionString"] as AnyObject?
        let version = nsObject as! String
        
        let urlPath: String = "https://api.github.com/repos/wcm-io-devops/aem-manager-osx/releases/latest"
        
        let task = URLSession.shared.dataTask(with: URL(string: urlPath)!, completionHandler: { (data, response, error) -> Void in
            do{
                let  str = try JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions.allowFragments) as![String:AnyObject]
                
                self.tagName = str["tag_name"] as! String
                if self.tagName.hasPrefix("v"){
                    self.tagName.remove(at: self.tagName.startIndex)
                    
                }
                
                os_log("Tagname: %@",type:.info,self.tagName )
                
            }
            catch {
                os_log("Can not fetch Version: %@",type:.error,error.localizedDescription )
            }
        })
        task.resume()
        os_log("Version: %@ --- Tagname: %@",type:.info,version,self.tagName )
        
        
        if version.versionToInt().lexicographicallyPrecedes(tagName.versionToInt()) {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "versionInfo"),sender: self)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        table.dataSource = self
        table.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.reloadTableData(_:)), name: NSNotification.Name(rawValue: "reload"), object: nil)
        
        initStatusBarItems()
    }
    
    func initStatusBarItems(){
        
        statusBarItems.forEach {
            item in item.removeFromStatusBar()
        }
        
        for instance in instances{
            if instance.showIcon {
                statusBarItems.append(StatusBarItem(target: self, instance: instance))
            }
        }
        
        
    }
    
    override var representedObject: Any? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    @IBAction func editInstance(_ sender: NSMenuItem) {
        editInstance()
    }
    
    func editInstance() {
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            
            // open preferences dialog with instance
            if let winCrtl = storyboard!.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "aemInstanceGUI")) as? NSWindowController {
                if let aemInstanceGui = winCrtl.contentViewController as? AemInstanceController{
                    // add data
                    aemInstanceGui.aeminstance = selectedInstance
                    aemInstanceGui.instances = instances
                    os_log("Edit Instance with name : %@ and id: %@",type:.info,aemInstanceGui.aeminstance!.name, aemInstanceGui.aeminstance!.id)
                }
                winCrtl.showWindow(self)
                guiarray.append(winCrtl)
            }
        }
        
    }
    
    @IBAction func doubleClickInstance(_ sender: NSObject) {
        if table.selectedRow >= 0 {
            editInstance()
        }
    }
    
    func openContextMenu() -> NSMenu? {
        if(selectedInstance != nil) {
            return InstanceMenu(target: self, instance: selectedInstance)
        }
        return nil
    }
    
    @IBAction func newInstance(_ sender: NSMenuItem) {
        
        // open new preferences dialog
        if let winCrtl = storyboard!.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "aemInstanceGUI")) as? NSWindowController {
            
            if let aemInstanceGui = winCrtl.contentViewController as? AemInstanceController{
                // add data
                aemInstanceGui.aeminstance = AEMInstance()
                aemInstanceGui.instances = instances
                
                os_log("New Instance with id: %@",type:.info, aemInstanceGui.aeminstance!.id)
            }
            winCrtl.showWindow(self)
            guiarray.append(winCrtl)
        }
        
    }
    
    @IBAction func deleteInstance(_ sender: NSMenuItem) {
        
        
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            if instances.contains(selectedInstance!){
                instances.remove(at: instances.index(of: selectedInstance!)!)
                
                AEMInstance.save(instances)
                
                NotificationCenter.default.post(name: Notification.Name(rawValue: "reload"), object: nil)
                
            }
        }
        
    }
    
    @IBAction func startInstance(_ sender: NSMenuItem) {
        
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            
            backgroundThread(background: {
                AemActions.startInstance(self.selectedInstance!)
                
            },completion: {
                
            })
        }
        
    }
    
    
    @objc func startInstance2(_ sender: InstanceMenuItem) -> Void {
        
        backgroundThread(background: {
            AemActions.startInstance(sender.ins)
        },completion: {
            
        })
    }
    
    
    @IBAction func stopInstance(_ sender: NSMenuItem) {
        
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            AemActions.stopInstance(selectedInstance!)
        }
    }
    
    @objc func stopInstance2(_ sender: InstanceMenuItem) {
        AemActions.stopInstance(sender.ins)
    }
    
    @IBAction func openAuthor(_ sender: NSMenuItem) {
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            if let url = URL(string: AEMInstance.getUrlWithContextPath(selectedInstance!)){
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc func openAuthor2(_ sender: InstanceMenuItem) {
        if let url = URL(string: AEMInstance.getUrlWithContextPath(sender.ins)){
            NSWorkspace.shared.open(url)
        }
        
    }
    
    @IBAction func openCRX(_ sender: NSMenuItem) {
        
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            openFuncCRX(selectedInstance!)
            
        }
    }
    
    @objc func openCRX2(_ sender: InstanceMenuItem) {
        openFuncCRX(sender.ins)
    }
    
    func openFuncCRX(_ instace: AEMInstance){
        var url = AEMInstance.getUrlWithContextPath(selectedInstance!)
        url.append("/crx/explorer/")
        if(selectedInstance?.type != AEMInstance.defaultType){
            url = AEMInstance.getUrl(instace)
            url.append("/crx/")
        }
        if let openUrl = URL(string:url){
            NSWorkspace.shared.open(openUrl)
        }
    }
    
    @IBAction func showHelp(_ sender: NSMenuItem) {
        
        let url = "https://docs.adobe.com/docs/en/aem/6-2/develop/ref.html"
        if let openUrl = URL(string:url){
            NSWorkspace.shared.open(openUrl)
        }
    }
    
    
    @IBAction func openCRXDE(_ sender: NSMenuItem) {
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            openCRXDEFunc(selectedInstance!)
        }
    }
    
    @IBAction func openInstanceFolder(_ sender: NSMenuItem) {
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            openInstanceFolderFunc(selectedInstance!)
        }
    }
    
    @objc func openInstanceFolder2(_ sender: InstanceMenuItem) {
        openInstanceFolderFunc(sender.ins)
    }
    
    func openInstanceFolderFunc(_ instance: AEMInstance){
        NSWorkspace.shared.selectFile(instance.path, inFileViewerRootedAtPath: "")
        
    }
    
    
    func openCRXDEFunc(_ instance : AEMInstance) {
        var url = AEMInstance.getUrlWithContextPath(instance)
        url.append("/crx/de/")
        if selectedInstance?.type != AEMInstance.defaultType {
            url = AEMInstance.getUrl(instance)
            url.append("/crxde")
        }
        
        // enable davex
        if selectedInstance?.type == AEMInstance.defaultType {
            AemActions.enableDavex(selectedInstance!)
        }
        
        if let openUrl = URL(string: url){
            NSWorkspace.shared.open(openUrl)
        }
    }
    
    @objc func openCRXDE2(_ sender: InstanceMenuItem) {
        openCRXDEFunc(sender.ins)
    }
    
    @IBAction func openFelixConsole(_ sender: NSMenuItem) {
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            openFelixConsoleFunc(selectedInstance!)
        }
    }
    
    func openFelixConsoleFunc(_ instance: AEMInstance){
        var url = AEMInstance.getUrlWithContextPath(instance)
        url.append("/system/console")
        if let openUrl = URL(string: url){
            NSWorkspace.shared.open(openUrl)
        }
    }
    
    @objc func openFelixConsole2(_ sender: InstanceMenuItem) {
        openFelixConsoleFunc(sender.ins)
    }
    
    @IBAction func openErrorLog(_ sender: NSMenuItem) {
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            openErrorLogFunc(selectedInstance!)
        }
    }
    
    @objc func openErrorLog2(_ sender: InstanceMenuItem) {
        NSApp.activate(ignoringOtherApps: true)
        
        self.view.window?.makeKeyAndOrderFront(self)
        self.view.window!.orderFront(self)
        openErrorLogFunc(sender.ins)
    }
    
    func openErrorLogFunc(_ instance: AEMInstance){
        openLogFile(instance, log: "error.log")
    }
    
    func openLogFile(_ instance:AEMInstance, log: String){
        var url = AEMInstance.getLogBaseFolder(instance)
        url.append(log)
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url){
            NSWorkspace.shared.openFile(url)
        }
    }
    
    @IBAction func openRequestLog(_ sender: NSMenuItem) {
        if table.selectedRow < 0 {
            performSegue(withIdentifier: NSStoryboardSegue.Identifier(rawValue: "noInstance"),sender: self)
        }else{
            openRequestLogFunc(selectedInstance!)
        }
    }
    
    @objc func openRequestLog2(_ sender: InstanceMenuItem) {
        openRequestLogFunc(sender.ins)
    }
    
    func openRequestLogFunc(_ instance: AEMInstance){
        openLogFile(instance, log: "request.log")
    }
    
    @objc func reloadTableData(_ notification: Notification){
        instances = AEMInstance.loadAEMInstances()
        table.reloadData()
        initStatusBarItems()
    }
    
}


extension ViewController: NSTableViewDataSource , NSTableViewDelegate {
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return instances.count
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        if let coid = tableColumn?.identifier {
            switch coid.rawValue {
            case "name": return instances[row].name
            case "path": return instances[row].path
            case "type": return instances[row].type
            case "status":
                let status = instances[row].status
                return status.rawValue;
                
            case "url": return AEMInstance.getUrl(instances[row])
            default: break
            }
            
        }
        return nil
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 {
            os_log("Selected instance in table with name : %@ and id: %@",type:.info,instances[table.selectedRow].name, instances[table.selectedRow].id)
            // set seletected instance
            selectedInstance = instances[table.selectedRow]
        }
        else {
            selectedInstance = nil
        }
    }

    
}

extension String {
    func versionToInt() -> [Int] {
        return self.components(separatedBy: ".")
            .map {
                Int.init($0) ?? 0
        }
    }
}

