//
//  LocalizationTranslateWindow.h
//  SpriteBuilder
//
//  Created by Benjamin Koatz on 6/4/14.
//
//

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>

@class LocalizationEditorLanguage;
@class LocalizationEditorWindow;
@class LocalizationTranslateWindowHandler;
@class ProjectSettings;

@interface LocalizationTranslateWindow : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTextViewDelegate, NSSplitViewDelegate, SKProductsRequestDelegate, NSWindowDelegate>
{
    //tab views
    IBOutlet NSView* _noActiveLangsView;
    IBOutlet NSView* _standardLangsView;
    IBOutlet NSView* _downloadingLangsView;
    IBOutlet NSView* _validatingPaymentView;
    IBOutlet NSView* _downloadingLangsErrorView;
    IBOutlet NSView* _downloadingCostsErrorView;
    IBOutlet NSView* _paymentErrorView;
    IBOutlet NSTabView* _translateFromTabView;
    
    //fields inside tab views
    IBOutlet NSTextField* _numWords;
    IBOutlet NSTextField* _cost;
    IBOutlet NSTextField* _noActiveLangsError;
    IBOutlet NSProgressIndicator* _languagesDownloading;
    IBOutlet NSProgressIndicator* _costDownloading;
    IBOutlet NSProgressIndicator* _paymentValidating;
    IBOutlet NSTextField* _costDownloadingText;
    IBOutlet NSButton* _ignoreText;
    
    //Language menus
    IBOutlet NSPopUpButton* _popTranslateFrom;
    IBOutlet NSTableView* _languageTable;
    IBOutlet NSButton* _checkAll;
    
    //Buttons
    IBOutlet NSButton* _cancel;
    IBOutlet NSButton *_buy;
    
    //Translations downloading stuff
    NSInteger _numTransToDownload;
    NSTimer* _timerTransDownload;
    
    //Language Info
    LocalizationEditorLanguage* _currLang;
    NSMutableDictionary* _languages;
    NSMutableArray* _activeLanguages;
    
    //Phrase Translation
    NSMutableArray* _phrasesToTranslate;
    NSInteger _tierForTranslations;
    
    //Product and URL interaction
    SKProduct* _product;
    NSString* _guid;
    NSMutableDictionary* _receipts;
    NSString* _latestRequestID;
    
    //Interaction with EditorWindow
    LocalizationEditorWindow* __weak _parentWindow;
    NSAlert* _buyAlert;
    NSString* _projectPathDir;
    NSString* _projectPath;
    
    //Used when closing
    NSURLSessionTask *_currTask;
}

- (id)initWithDownload:(ProjectSettings *)ps parentWindow:(LocalizationEditorWindow*)pw;
- (IBAction)buy:(id)sender;
- (IBAction)cancel:(id)sender;
- (IBAction)toggleIgnore:(id)sender;
- (IBAction)selectedTranslateFromMenu:(id)sender;
- (IBAction)toggleCheckAll:(id)sender;
- (IBAction)retryLanguages:(id)sender;
- (IBAction)retryCost:(id)sender;
- (void)cancelDownloadWithError:(NSError*)error;
- (void)pauseDownload;
- (void)restartDownload;
- (void)refresh;

//Needed for Transaction Observer
-(void)enableAll;
-(void)validateReceipt:(NSString *)receipt;
-(void)saveReceipt:(NSData*)receipt transaction:(SKPaymentTransaction*)transaction;
-(void)setPaymentError;

@property (nonatomic,readwrite) NSInteger numTransToDownload;
@property (nonatomic,strong) NSTimer* timerTransDownload;
@property (nonatomic,strong) LocalizationEditorLanguage* currLang;
@property (nonatomic,strong) NSMutableDictionary* languages;
@property (nonatomic,strong) NSMutableArray* activeLanguages;
@property (nonatomic,strong) NSMutableArray* phrasesToTranslate;
@property (nonatomic,readwrite) NSInteger tierForTranslations;
@property (nonatomic,strong) SKProduct* product;
@property (nonatomic,copy) NSString* guid;
@property (nonatomic,strong) NSMutableDictionary* receipts;
@property (nonatomic,copy) NSString* latestRequestID;

@property (nonatomic,weak) LocalizationEditorWindow* parentWindow;
@property (nonatomic,strong) NSAlert* buyAlert;
@property (nonatomic,strong) NSString* projectPathDir;
@property (nonatomic,strong) NSString* projectPath;
@property (nonatomic,strong) NSURLSessionTask* currTask;
@end