//
//  LocalizationTranslateWindow.m
//  SpriteBuilder
//
//  Created by Benjamin Koatz on 6/4/14.
//
//

#import "LocalizationTranslateWindow.h"
#import "LocalizationEditorHandler.h"
#import "AppDelegate.h"
#import "LocalizationEditorLanguage.h"
#import "LocalizationEditorTranslation.h"
#import "LocalizationEditorWindow.h"
#import "SBErrors.h"
#import "ProjectSettings.h"
#import "CocosScene.h"
#import "StringPropertySetter.h"
#import "TranslationSettings.h"

@implementation LocalizationTranslateWindow

@synthesize numTransToDownload = _numTransToDownload;
@synthesize timerTransDownload = _timerTransDownload;
@synthesize currLang = _currLang;
@synthesize languages = _languages;
@synthesize activeLanguages = _activeLanguages;
@synthesize phrasesToTranslate = _phrasesToTranslate;
@synthesize tierForTranslations = _tierForTranslations;
@synthesize product = _product;
@synthesize guid = _guid;
@synthesize receipts = _receipts;
@synthesize latestRequestID = _latestRequestID;
@synthesize parentWindow = _parentWindow;
@synthesize buyAlert = _buyAlert;
@synthesize projectPathDir = _projectPathDir;
@synthesize projectPath = _projectPath;
@synthesize currTask = _currTask;

//Standards for the tab view
static int downloadLangsIndex = 0;
static int noActiveLangsIndex = 1;
static int standardLangsIndex = 2;
static int validatingPaymentIndex = 3;
static int downloadCostErrorIndex = 4;
static int downloadLangsErrorIndex = 5;
static int paymentErrorIndex = 6;

//URLs
static NSString* const baseURL = @"http://www.spritebuilder.com/api/v1";
static NSString* languageURL;
static NSString* estimateURL;
static NSString* receiptTranslationsURL;
static NSString* translationsURL;
static NSString* cancelURL;

//Repeated messages for the user
static NSString* const noActiveLangsString = @"No Valid Languages";
static NSString* const downloadingLangsString = @"Downloading...";
static NSString* noActiveLangsErrorString = @"We support translations from:\r\r%@.";

//Interval for repeating a downlaod request, in seconds
static double downloadRepeatInterval = 60;

//Amount of server downtime allowed until download cancelled, in seconds
static double serverTimeOut = 86400; //86400 = 24 hours

//Number of intervals where the server has been unavailable
static int numTimedOutIntervals = 0;

#pragma mark Initializing
/*
 * Set up URLs and global variables and initialize with the information to restart a download request.
 * Used when restarting a download request without showing the window
 */
-(id)initWithDownload:(ProjectSettings *)ps parentWindow:(LocalizationEditorWindow*)pw{
    self = [super init];
    if (!self)
    {
      return NULL;
    }
    [self setUpURLsAndGlobals];
    self.projectPathDir = ps.projectPathDir;
    self.projectPath = ps.projectPath;
    self.latestRequestID = ps.latestRequestID;
    self.parentWindow = pw;
    self.numTransToDownload = ps.numToDownload;
    return self;
}

/*
 * Set up URLs and global variables and prepare the tab views, disable everything in the window until the 
 * languages are downloaded and get the available languages from the server.
 * Used when opening a new translation window.
 */
-(void) awakeFromNib
{
    [self setUpURLsAndGlobals];
    ProjectSettings *ps = ((ProjectSettings*)[[AppDelegate appDelegate] projectSettings]);
    self.projectPathDir = ps.projectPathDir;
    self.projectPath = ps.projectPath;
    [[_translateFromTabView tabViewItemAtIndex:downloadLangsIndex] setView:_downloadingLangsView];
    [[_translateFromTabView tabViewItemAtIndex:noActiveLangsIndex] setView:_noActiveLangsView];
    [[_translateFromTabView tabViewItemAtIndex:standardLangsIndex] setView:_standardLangsView];
    [[_translateFromTabView tabViewItemAtIndex:validatingPaymentIndex] setView:_validatingPaymentView];
    [[_translateFromTabView tabViewItemAtIndex:downloadCostErrorIndex] setView:_downloadingCostsErrorView];
    [[_translateFromTabView tabViewItemAtIndex:downloadLangsErrorIndex] setView:_downloadingLangsErrorView];
    [[_translateFromTabView tabViewItemAtIndex:paymentErrorIndex] setView:_paymentErrorView];
    [self disableAllExceptButtons];
    [self getLanguagesFromServer];
    
}

/*
 * Set up URLs and global variables like guid and language translation mapping dictionary.
 */
-(void)setUpURLsAndGlobals{
    languageURL = [baseURL stringByAppendingString:@"/translations/languages?key=%@"];
    estimateURL = [baseURL stringByAppendingString:@"/translations/estimate"];
    receiptTranslationsURL = [baseURL stringByAppendingString:@"/translations"];
    translationsURL = [baseURL stringByAppendingString:@"/translations?key=%@"];
    cancelURL = [baseURL stringByAppendingString:@"/translations/cancel"];
    
    self.guid = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] objectForKey:@"sbUserID"];
    self.languages = [[NSMutableDictionary alloc] init];
    self.receipts = [[NSMutableDictionary alloc] init];
    self.buyAlert = [NSAlert alertWithMessageText:@"Starting Translation Download" defaultButton:@"Continue" alternateButton:@"Cancel" otherButton:NULL informativeTextWithFormat:@"The average translation download wait is 30 minutes, but translation downloads can sometimes take days. Downloads are nonrefundable, and during a translation download the contents of the Language Editor window can't be modified."];
    [self.buyAlert setShowsSuppressionButton:YES];
    
}

#pragma mark Downloading and Updating Languages

/*
 * Show the downloading languages message.
 * Get languages from server and update active langauges. Once the session 
 * is done the JSON data will be parsed if there wasn't an error. Errors handled and
 * displayed.
 */
-(void)getLanguagesFromServer{
    _popTranslateFrom.title = downloadingLangsString;
    [_translateFromTabView selectTabViewItemAtIndex:downloadLangsIndex];
    [_languagesDownloading startAnimation:self];
    NSString* URLstring =[NSString stringWithFormat:languageURL, _guid];
    NSURL* url = [NSURL URLWithString:URLstring];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL: url
                                                             completionHandler:^(NSData *data,
                                                                                 NSURLResponse *response,
                                                                                 NSError *error)
                                  {
                                      if (!error)
                                      {
                                          [self parseJSONLanguages:data];
                                          NSLog(@"Languages Status code: %li", ((NSHTTPURLResponse *)response).statusCode);
                                      }
                                      else
                                      {
                                          [_languagesDownloading stopAnimation:self];
                                          [_translateFromTabView selectTabViewItemAtIndex:downloadLangsErrorIndex];
                                          NSLog(@"Languages Error: %@", error.localizedDescription);
                                      }
                                  }];
    [task resume];
    _currTask = task;
}


/*
 * Turns the JSON response into a dictionary and fill the _languages global accordingly.
 * Then update the active languages array, the pop-up menu and the table. This is
 * only done once in the beginning of the session. Errors handled and displayed.
 */
-(void)parseJSONLanguages:(NSData *)data{
    NSError *JSONError;
    NSMutableDictionary* availableLanguagesDict = [NSJSONSerialization JSONObjectWithData:data
                                                                                  options:NSJSONReadingMutableContainers error:&JSONError];
    if(JSONError || [[[availableLanguagesDict allKeys] firstObject] isEqualToString:@"Error"])
    {
        [self printJSONOrNormalErrorForFunction:@"Languages" JSONError:JSONError Error:[availableLanguagesDict objectForKey:@"Error"]];
        [_languagesDownloading stopAnimation:self];
        [_translateFromTabView selectTabViewItemAtIndex:downloadLangsErrorIndex];
        return;
    }
    for(NSString* lIso in availableLanguagesDict.allKeys)
    {
        NSMutableArray* translateTo = [[NSMutableArray alloc] init];
        for(NSString* translateToIso in (NSArray *)[availableLanguagesDict objectForKey:lIso])
        {
            [translateTo addObject:[[LocalizationEditorLanguage alloc] initWithIsoLangCode:translateToIso]];
        }
        [_languages setObject:translateTo forKey:[[LocalizationEditorLanguage alloc] initWithIsoLangCode:lIso]];
    }
    [self updateActiveLanguages];
    [self finishLanguageSetUp];
}

/*
 * Remove active languages not in the keys of the global languages dictionary
 */
-(void)updateActiveLanguages{
    LocalizationEditorHandler* handler = [AppDelegate appDelegate].localizationEditorHandler;
    _activeLanguages = [[NSMutableArray alloc] initWithArray:handler.activeLanguages];
    NSMutableArray* activeLangsCopy = _activeLanguages.copy;
    for(LocalizationEditorLanguage* l in activeLangsCopy)
    {
        if(![[_languages allKeys] containsObject:l])
        {
            [_activeLanguages removeObject:l];
        }
    }
}

/*
 * Once the languages are retrieved, this is called. The spinning wheel and 
 * message indicating downloading languages are hidden. All languages' quickEdit
 * settings are checked off, and if there are active languages, the pop-up
 * 'translate from' menu is set up and, in that function, the language table's
 * data is reloaded.
 * If there are no active languages that we can translate from
 * then a the pop-up menu is disabled, an error message is shown.
 */
-(void)finishLanguageSetUp{
    
    [_languagesDownloading stopAnimation:self];
    [self uncheckLanguageDict];
    if(_activeLanguages.count)
    {
        LocalizationEditorLanguage* l = [_activeLanguages objectAtIndex:0];
        _currLang = l;
        _popTranslateFrom.title = l.name;
        [self enableAllExceptButtons];
        [_translateFromTabView selectTabViewItemAtIndex:standardLangsIndex];
        [self updateLanguageSelectionMenu:0];
    }
    else
    {
        _currLang = NULL;
        _popTranslateFrom.title = noActiveLangsString;
        [self updateNoActiveLangsError];
        [_translateFromTabView selectTabViewItemAtIndex:noActiveLangsIndex];
    }
}

/*
 * If this is coming out of an instance where the language selection menu has to be 
 * updated without a user selection (the initial post-download call) everything is normal. But
 * if this is just a normal user selection, and the user reselected the current language, 
 * ignore this and return.
 *
 * Otherwise, remove all items from the menu, then put all the active langauges back into it.
 * Set the global currLang to the newly selected language and then update the main language 
 * table and the check-all box accordingly. Dispatch get main queue is used because it makes this work.
 */
- (void) updateLanguageSelectionMenu:(int)userSelection
{
    
    NSString* newLangSelection = _popTranslateFrom.selectedItem.title;
    if(userSelection && [newLangSelection isEqualToString:_currLang.name])
    {
        return;
    }
    if(!_currLang)
    {
        newLangSelection = ((LocalizationEditorLanguage*)[_activeLanguages objectAtIndex:0]).name;
    }
    
    [_popTranslateFrom removeAllItems];
    NSMutableArray* langTitles = [NSMutableArray array];
    for (LocalizationEditorLanguage* lang in _activeLanguages)
    {
        if([lang.name isEqualToString:newLangSelection])
        {
            _currLang = lang;
        }
        [langTitles addObject:lang.name];
    }
    
    [_popTranslateFrom addItemsWithTitles:langTitles];
    
    if (newLangSelection)
    {
        [_popTranslateFrom selectItemWithTitle:newLangSelection];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [_languageTable reloadData];
    });
    [self updateCheckAll];
    
}

/*
 * Called when window reopened, just in case things were changed on the editor window
 */
-(void)refresh{
    [self updateActiveLanguages];
    [self finishLanguageSetUp];
    [_languageTable reloadData];
    [self getCostEstimate];
}

#pragma mark Downloading Cost Estimate and Word Count

/*
 * Gets the estimated cost of a translation request using the currrent user-set parameters.
 * Updates phrases to translate, returning the number of phrases the user is asking to
 * translate. Set both the number of words and the cost to 0 if there are 0 phrases to
 * translate.
 *
 * We then start the spinning download image and a download message, and send the array of 
 * phrases as a post request to the the 'estimate' spritebuilder URL, and receive the number 
 * of the appropriate Apple Price Tier and the number of words that are in the the phrase we
 * want to translate. We then send that price tier to Apple to come up with the appropriate, 
 * localized price.
 */
-(void)getCostEstimate{
    [self disableAllExceptButtons];
    [_translateFromTabView selectTabViewItemAtIndex:standardLangsIndex];
    NSInteger phrases = [self updatePhrasesToTranslate];
    if(phrases == 0)
    {
        _cost.stringValue = _numWords.stringValue = @"0";
        [_buy setEnabled:0];
        [self enableAllExceptButtons];
        return;
    }
    [_costDownloading setHidden:0];
    [_costDownloadingText setHidden:0];
    [_costDownloading startAnimation:self];
     NSDictionary *JSONObject = [[NSDictionary alloc] initWithObjectsAndKeys:
                                 _guid,@"key",
                                 _phrasesToTranslate,@"phrases",
                                 nil];
     NSError *error;
     NSData *postdata = [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:&error];
    if(error)
    {
        NSLog(@"Error: %@", error);
    }
     NSURL *url = [NSURL URLWithString:estimateURL];
     NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
     request.HTTPMethod = @"POST";
     request.HTTPBody = postdata;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
     NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request
                                                                  completionHandler:^(NSData *data,
                                                                                      NSURLResponse *response,
                                                                                      NSError *error)
                                   {
                                       if (!error)
                                       {
                                           [self parseJSONEstimate:data];
                                           if(_tierForTranslations > 0)
                                           {
                                               [self requestIAPProducts];
                                           }
                                           else
                                           {
                                               [self enableAllExceptButtons];
                                               [_costDownloading stopAnimation:self];
                                               [_costDownloading setHidden:1];
                                               [_costDownloadingText setHidden:1];
                                               [_translateFromTabView selectTabViewItemAtIndex:downloadCostErrorIndex];
                                           }
                                           NSLog(@"Estimate Status code: %li", ((NSHTTPURLResponse *)response).statusCode);
                                       }
                                       else
                                       {
                                           [self enableAllExceptButtons];
                                           [_costDownloading stopAnimation:self];
                                           [_costDownloading setHidden:1];
                                           [_costDownloadingText setHidden:1];
                                           [_translateFromTabView selectTabViewItemAtIndex:downloadCostErrorIndex];
                                           NSLog(@"Estimate Error: %@", error.localizedDescription);
                                       }
                                   }];
     [task resume];
    _currTask = task;
}

/*
 * Goes through every LocalizationEditorTranslation, first seeing if there is a
 * version of the phrase in the 'translate from' language that isn't null or just 
 * whitespace.
 * Then it populates an array of the isoCodes for every language the phrase should be
 * translated to. (If we are ignoring already translated text, this is every language
 * with 'quick edit' enable. If we aren't, this is only those translations that don't
 * have a translation string already.)
 * If that array remains unpopulated, then we ignore this translation. Else we then add the
 * count of the array to the number of tranlsations to download (for the progress bar later). 
 * Then we create a dictionary of the 'translate from' text, the context (if it exists), the
 * source language (currLang), the languages to translate to and add that dictionary to an array
 * of phrases.
 *
 * Return the number of phrases to translate.
 */
-(NSInteger)updatePhrasesToTranslate{
    LocalizationEditorHandler* handler = [AppDelegate appDelegate].localizationEditorHandler;
    NSMutableArray* trans = handler.translations;
    _phrasesToTranslate = [[NSMutableArray alloc] init];
    _numTransToDownload = 0;
    for(LocalizationEditorTranslation* t in trans)
    {
        NSString* toTranslate = [t.translations objectForKey:_currLang.isoLangCode];
        NSCharacterSet *set = [NSCharacterSet whitespaceCharacterSet];
        if(!toTranslate || [toTranslate isEqualToString:@""]
           || ([[toTranslate stringByTrimmingCharactersInSet: set] length] == 0))
        {
            continue;
        }
        NSMutableArray* langsToTranslate = [[NSMutableArray alloc] init];
        for(LocalizationEditorLanguage* l in [_languages objectForKey:_currLang])
        {
            NSString* tempTrans = [t.translations objectForKey:l.isoLangCode];
            if((!tempTrans  || [tempTrans isEqualToString:@""]) || !_ignoreText.state)
            {
                if(l.quickEdit)
                {
                    [langsToTranslate addObject:l.isoLangCode];
                }
            }
        }
        if(!langsToTranslate.count)
        {
            continue;
        }
        _numTransToDownload += langsToTranslate.count;
        NSDictionary *phrase;
        if(t.comment && ![t.comment isEqualToString:@""])
        {
            phrase = [[NSDictionary alloc] initWithObjectsAndKeys:
                      [t.translations objectForKey:_currLang.isoLangCode], @"text",
                      t.comment, @"context",
                      _currLang.isoLangCode,@"source_language",
                      langsToTranslate,@"target_languages",
                      nil];
        }
        else
        {
            phrase = [[NSDictionary alloc] initWithObjectsAndKeys:
                      [t.translations objectForKey:_currLang.isoLangCode], @"text",
                      _currLang.isoLangCode,@"source_language",
                      langsToTranslate,@"target_languages",
                      nil];
        }
        [_phrasesToTranslate addObject:phrase];
    }
    return _phrasesToTranslate.count;
}

/*
 * Parses the JSON response from a request for a cost estimate. Sets the tier for
 * translations, and the number of words we asked to translate as determined by
 * the server. Handles error and sets the translation tier and number of words.
 */
-(void)parseJSONEstimate:(NSData*)data{
    NSError *JSONerror;
    NSDictionary* dataDict  = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&JSONerror];
    if(JSONerror || [[[dataDict allKeys] firstObject] isEqualToString:@"Error"])
    {
        [self printJSONOrNormalErrorForFunction:@"Estimate" JSONError:JSONerror Error:[dataDict objectForKey:@"Error"]];
        [self enableAllExceptButtons];
        [_costDownloading stopAnimation:self];
        [_costDownloading setHidden:1];
        [_costDownloadingText setHidden:1];
        [_translateFromTabView selectTabViewItemAtIndex:downloadCostErrorIndex];
        return;
    }
    _tierForTranslations  = [[dataDict objectForKey:@"iap_price_tier"] intValue];
    _numWords.stringValue = [[dataDict objectForKey:@"wordcount"] stringValue];
}

/*
 * Get the IAP PIDs from the correct plist, put those into a Products Request and start that request.
 */
-(void)requestIAPProducts{
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"LocalizationInAppPurchasesPIDs" withExtension:@".plist"];
    NSSet* identifierSet = [NSSet setWithObject:[[NSArray arrayWithContentsOfURL:url] objectAtIndex:(_tierForTranslations-1)]];
    SKProductsRequest* request = [[SKProductsRequest alloc] initWithProductIdentifiers:identifierSet];
    [request setDelegate:self];
    [request start];
}

#pragma mark Toggling/Clicking Button Events

/*
 * Solicit a payment after showing a warning about long download times.
 */
- (IBAction)buy:(id)sender {
    NSInteger continueDownload;
    if(![[AppDelegate appDelegate] showHelpDialog:@"longDownloadTime"])
	{
        return;
    }
    continueDownload = [_buyAlert runModal];
    if ([[_buyAlert suppressionButton] state] == NSOnState)
    {
        [[AppDelegate appDelegate] disableHelpDialog:@"longDownloadTime"];
    }
    if((continueDownload == NSAlertDefaultReturn) && [SKPaymentQueue canMakePayments])
    {
        [[AppDelegate appDelegate].lto setLtw:self];
        SKPaymentQueue* defaultQueue = [SKPaymentQueue defaultQueue];
        SKPayment* payment = [SKPayment paymentWithProduct:_product];
        [defaultQueue addPayment:payment];
        [_paymentValidating startAnimation:self];
        [_translateFromTabView selectTabViewItemAtIndex:validatingPaymentIndex];
        [self disableAll];
    }
}

/*
 * Close the window.
 */
- (IBAction)cancel:(id)sender {
    [NSApp endSheet:self.window];
    [self.window close];
}

/*
 * If a user clicks or unclicks ignore then update the cost of the translations
 * they are seeking.
 */
- (IBAction)toggleIgnore:(id)sender {
    [self getCostEstimate];
}

/*
 * Update the langauge select menu if someone has selected the pop-up
 * 'translate from' menu. Send 1 because this is a
 * user-click generated event.
 */
- (IBAction)selectedTranslateFromMenu:(id)sender {
    [self updateLanguageSelectionMenu:1];
}

/*
 * If the check all box has been clicked, turn off mixed state (so
 * people can only go from no check to check) and update the quickEdit
 * state of all languages in the array of 'translate to' langauges for 
 * the current language and reload the main language table.
 */
- (IBAction)toggleCheckAll:(id)sender {
    _checkAll.allowsMixedState = 0;
    for (LocalizationEditorLanguage* l in [_languages objectForKey:_currLang])
    {
        l.quickEdit = _checkAll.state;
    }
    [_languageTable reloadData];
}

/*
 * Clicked if there was an error in downloading languages and the user
 * wants to retry
 */
- (IBAction)retryLanguages:(id)sender {
    [self getLanguagesFromServer];
}

/*
 * Clicked if there was an error in downloading cost Estimate and the user
 * wants to retry
 */
- (IBAction)retryCost:(id)sender {
    [self getCostEstimate];
}

#pragma mark Update Error Strings and the 'Check All' Button

/*
 * Put all the available 'translate from' languages in the no active languages error
 */
-(void)updateNoActiveLangsError{
    
    NSMutableString* s = [[NSMutableString alloc] initWithString:@""];
    for(LocalizationEditorLanguage* l in [_languages allKeys])
    {
        if(![s isEqualToString:@""])
        {
            [s appendString:@"\r\r"];
        }
        [s appendString:l.name];
    }
    _noActiveLangsError.stringValue = [NSString stringWithFormat:noActiveLangsErrorString, s];
}

/*
 * Go through the dictionary of 'translate to' languages for the current language
 * and update the check all box accordingly
 */
-(void)updateCheckAll{
    BOOL checkAllFalse = 0;
    BOOL checkAllTrue = 1;
    for(LocalizationEditorLanguage* l in [_languages objectForKey:_currLang])
    {
        if(!l.quickEdit)
        {
            checkAllTrue = 0;
        }
        else
        {
            checkAllFalse = 1;
        }
    }
    if(checkAllFalse && !checkAllTrue)
    {
        _checkAll.allowsMixedState = 1;
        _checkAll.state = -1;
    }
    else if(!checkAllFalse)
    {
        _checkAll.allowsMixedState = 0;
        _checkAll.state = 0;
    }
    else
    {
        _checkAll.allowsMixedState = 0;
        _checkAll.state = 1;
    }
}

#pragma mark Table View Delegate

/*
 * If there's no current language then there's going to be nothing to
 * put in the tableView, so just return 0 for the size. Else, get the 
 * cost with the updated parameters and return the count of the array
 * of 'translate to' languages associate with the current language.
 */
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    
    if(!_currLang)
    {
        return 0;
    }
    [self getCostEstimate];
    return ((NSArray*)[_languages objectForKey:_currLang]).count;
}

/*
 * If there's no current language then there's going to be nothing to put in the tableView, 
 * so just return 0. Else, just return the values for stuff from the 'translate from' array 
 * for the current language.
 */
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    if(!_currLang)
    {
     return 0;
    }
    if ([aTableColumn.identifier isEqualToString:@"enabled"])
    {
        LocalizationEditorLanguage* lang = [((NSArray*)[_languages objectForKey:_currLang]) objectAtIndex:rowIndex];
        return [NSNumber numberWithBool:lang.quickEdit];
    }
    else if ([aTableColumn.identifier isEqualToString:@"name"])
    {
        LocalizationEditorLanguage* lang = [((NSArray*)[_languages objectForKey:_currLang]) objectAtIndex:rowIndex];
        return lang.name;
    }
    return NULL;
}

/*
 * Update the check all box and get new cost when the user toggles one of the languages in the main language table.
 */
- (void) tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
    if ([tableColumn.identifier isEqualToString:@"enabled"])
    {
        LocalizationEditorLanguage* lang = [((NSArray*)[_languages objectForKey:_currLang]) objectAtIndex:row];
        lang.quickEdit = [object boolValue];
        [self updateCheckAll];
        [self getCostEstimate];
    }
}

#pragma mark Product Request Delegate

/*
 * If product request fails, say that the cost estimate failed.
 */
-(void) request:(SKRequest *)request didFailWithError:(NSError *)error{
    [self enableAllExceptButtons];
    [_costDownloading stopAnimation:self];
    [_costDownloading setHidden:1];
    [_costDownloadingText setHidden:1];
    [_translateFromTabView selectTabViewItemAtIndex:downloadCostErrorIndex];
    NSLog(@"Product Request Failed: %@", error.localizedDescription);
}

/*
 * Takes in the products returned by apple, prints any invalid identifiers and displays
 * the price of those products.
 */
-(void) productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response{
    _product = response.products[0];
    for(NSString *invalidIdentifier in response.invalidProductIdentifiers)
    {
        [_translateFromTabView selectTabViewItemAtIndex:downloadCostErrorIndex];
        [self enableAllExceptButtons];
        [_costDownloading stopAnimation:self];
        [_costDownloading setHidden:1];
        [_costDownloadingText setHidden:1];
        NSLog(@"Invalid Identifier: %@",invalidIdentifier);
        return;
    }
    [self displayPrice];
}

#pragma mark Validate Receipt and Set Up Downloading Translations

/*
 * Validates the receipt with our server. If receipt is valid, set up timer for future
 * 'get translation' events, and close the translation window. Also, set up the main editor
 * window for its 'downloading translations' phase.
 */
-(void)validateReceipt:(NSString *)receipt{
    NSDictionary *JSONObject = [[NSDictionary alloc] initWithObjectsAndKeys: _guid,@"key",receipt,@"receipt",_phrasesToTranslate,@"phrases",nil];
    NSError *error;
    NSData *postdata2 = [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:&error];
    NSURL *url = [NSURL URLWithString:receiptTranslationsURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postdata2;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request
                                                             completionHandler:^(NSData *data,
                                                                                 NSURLResponse *response,
                                                                                 NSError *error)
                                  {
                                      if (!error)
                                      {
                                          if(![self parseJSONConfirmation:data])
                                          {
                                              
                                                  ProjectSettings* ps = [AppDelegate appDelegate].projectSettings;
                                                  ps.numToDownload = _numTransToDownload;
                                                  [ps store];
                                                  [self getTranslations];
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                  _timerTransDownload = [NSTimer scheduledTimerWithTimeInterval:downloadRepeatInterval target:self selector:@selector(getTranslations) userInfo:nil repeats:YES];
                                                  [NSApp endSheet:self.window];
                                                  [self.window close];
                                                  [self setLanguageWindowDownloading];
                                                  LocalizationEditorHandler* handler = [AppDelegate appDelegate].localizationEditorHandler;
                                                  [handler setEdited];
                                              });
                                              [self enableAll];
                                              [_paymentValidating stopAnimation:self];
                                              [_translateFromTabView selectTabViewItemAtIndex:standardLangsIndex];
                                          }
                                          NSLog(@"Receipt Validation status code: %li", ((NSHTTPURLResponse *)response).statusCode);
                                      }
                                      else
                                      {
                                          [self enableAll];
                                          [_translateFromTabView selectTabViewItemAtIndex:paymentErrorIndex];
                                          NSLog(@"Receipt Validation error: %@", error.localizedDescription);
                                      }
                                  }];
    [task resume];
    _currTask = task;
}

/*
 * JSON confirmation just gives latest request ID. Put that in the project settings.
 */
-(int)parseJSONConfirmation:(NSData *)data{
    NSError *JSONError;;
    NSDictionary* initialTransDict  = [NSJSONSerialization JSONObjectWithData:data
                                                                    options:kNilOptions error:&JSONError];
    if(JSONError || [[[initialTransDict allKeys] firstObject] isEqualToString:@"Error"])
    {
        [self printJSONOrNormalErrorForFunction:@"Request Confirmation" JSONError:JSONError Error:[initialTransDict objectForKey:@"Error"]];
        [self enableAll];
        [_paymentValidating stopAnimation:self];
        [_translateFromTabView selectTabViewItemAtIndex:paymentErrorIndex];
        return -1;
    }
    _latestRequestID = [initialTransDict objectForKey:@"request_id"];
    ProjectSettings* ps = [AppDelegate appDelegate].projectSettings;
    ps.latestRequestID = _latestRequestID;
    [ps store];
    return 0;
}

/*
 * Set the 'downloading languages' for each translation and call the localization editor
 * window's own 'set downloading translations' function.
 */
-(void)setLanguageWindowDownloading{
    LocalizationEditorHandler* handler = [AppDelegate appDelegate].localizationEditorHandler;
    NSArray* translations = handler.translations;
    for(LocalizationEditorTranslation* t in translations)
    {
        for(NSDictionary* d in _phrasesToTranslate)
        {
            NSString* sourceText = [t.translations objectForKey:[d objectForKey:@"source_language"]];
            if([sourceText isEqualToString:[d objectForKey:@"text"]] && [t.comment isEqualToString:[d objectForKey:@"context"]])
            {
                t.languagesDownloading = [NSMutableArray arrayWithArray:[d objectForKey:@"target_languages"]];
                [_parentWindow addLanguages:[d objectForKey:@"target_languages"]];
            }
        }
    }
    [_parentWindow setDownloadingTranslations];
}

#pragma mark Download Translations

/*
 * Get translations for the user and parse them into the current localization editor window.
 */
-(void)getTranslations{
    NSString* URLstring = [NSString stringWithFormat:translationsURL, _guid];
    NSURL* url = [NSURL URLWithString:URLstring];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL: url
                                                             completionHandler:^(NSData *data,
                                                                                 NSURLResponse *response,
                                                                                 NSError *error)
                                  {
                                      if (!error)
                                      {
                                          if(![self parseJSONTranslations:data])
                                          {
                                              numTimedOutIntervals = 0;
                                          }
                                          NSLog(@"Translations Status code: %li", ((NSHTTPURLResponse *)response).statusCode);
                                      }
                                      else
                                      {
                                          numTimedOutIntervals++;
                                          if(numTimedOutIntervals*downloadRepeatInterval >= serverTimeOut)
                                          {
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                  [_parentWindow finishDownloadingTranslations];
                                                  [self cancelDownloadWithError:error];
                                                  NSAlert* alert = [NSAlert alertWithMessageText:@"Translation Download Failed" defaultButton:@"OK" alternateButton:NULL otherButton:NULL informativeTextWithFormat:@"Your download has failed due to an error on our servers. Please contact customer service for a full refund."];
                                                  [alert runModal];
                                              });
                                          }
                                          NSLog(@"Translations Error: %@", error.localizedDescription);
                                      }
                                  }];
    [task setTaskDescription:@"translations"];
    [task resume];
    _currTask = task;
}

/*
 * Find the current request in the response dictionary, and parse out translations
 * from the phrases and put them into the handler's translation objects. Then increment
 * the parent's download progress indicator by one, and, when the download is done,
 * end it here and finish it in the window.
 */
-(int)parseJSONTranslations:(NSData *)data{
    NSError *JSONerror;
    ProjectSettings* ps = [AppDelegate appDelegate].projectSettings;
    NSDictionary* initialTransDict  = [NSJSONSerialization JSONObjectWithData:data
                                                                                  options:NSJSONReadingMutableContainers error:&JSONerror];
    if(JSONerror || [[[initialTransDict allKeys] firstObject] isEqualToString:@"Error"])
    {
        numTimedOutIntervals++;
        if(numTimedOutIntervals*downloadRepeatInterval >= serverTimeOut)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [_parentWindow finishDownloadingTranslations];
                [self cancelDownloadWithError:JSONerror];
                NSAlert* alert = [NSAlert alertWithMessageText:@"Translation Download Failed" defaultButton:@"OK" alternateButton:NULL otherButton:NULL informativeTextWithFormat:@"Your download has failed due to an error on our servers. Please contact customer service for a full refund."];
                [alert runModal];
            });
        }
        NSLog(@"Translations JSONError: %@", JSONerror.localizedDescription);
        return -1;
    }
    BOOL isCurrentProjectOpen = [ps.projectPathDir isEqualToString:_projectPathDir];
    LocalizationEditorHandler* handler;
    if(isCurrentProjectOpen)
    {
        handler = [AppDelegate appDelegate].localizationEditorHandler;
    }
    else
    {
        
        NSMutableDictionary* projectDict = [NSMutableDictionary dictionaryWithContentsOfFile:_projectPath];
        if(!projectDict)
        {
            [self cannotFindProjectAlert:_projectPath];
            [self pauseDownload];
            return -1;
        }
        ps = [[ProjectSettings alloc] initWithSerialization:projectDict];
        if(!ps)
        {
            [self cannotFindProjectAlert:_projectPath];
            [self pauseDownload];
            return -1;
        }
        ps.projectPath = _projectPath;
        [ps store];
        handler = [[LocalizationEditorHandler alloc] init];
        NSString* langFile = nil;
        for(NSDictionary *rp in ps.resourcePaths)
        {
            NSString *tempLangFile = [_projectPathDir stringByAppendingPathComponent:[[rp objectForKey:@"path"] stringByAppendingPathComponent:@"Strings.ccbLang"]];
            if([[NSFileManager defaultManager] fileExistsAtPath:tempLangFile])
            {
                langFile = tempLangFile;
            }
        }
        if(!langFile)
        {
            [self cannotFindProjectAlert:_projectPath];
            [self pauseDownload];
            return -1;
        }
        [handler setManagedFileForBackgroundTranslationDownload:langFile];
    }
    NSArray* handlerTranslations = handler.translations;
    NSArray* requests = [initialTransDict objectForKey:@"requests"];
    NSDictionary* request = NULL;
    for(NSDictionary* r in requests)
    {
        if([[r objectForKey:@"id"] isEqualToString:_latestRequestID])
        {
            request = r;
            break;
        }
    }
    NSArray* phrases = [request objectForKey:@"phrases"];
    for(NSDictionary* phrase in phrases)
    {
        NSString* text = [phrase objectForKey:@"text"];
        NSString* context = [phrase objectForKey:@"context"];
        NSString* sourceLangIso = [phrase objectForKey:@"source_language"];
        NSArray* serverTranslations = [phrase objectForKey:@"translations"];
        for(NSDictionary* translation in serverTranslations)
        {
            NSString* translationIso = [translation objectForKey:@"target_language"];
            NSString* translationStatus = [translation objectForKey:@"status"];
            NSString* translationText = [translation objectForKey:@"translated_text"];
            if([translationStatus isEqualToString:@"received"])
            {
                for(LocalizationEditorTranslation* t in handlerTranslations)
                {
                    NSString* sourceText = [t.translations objectForKey:sourceLangIso];
                    if([sourceText isEqualToString:text] && [t.comment isEqualToString:context] && [t.languagesDownloading containsObject:translationIso])
                    {
                        [t.translations setObject:translationText forKey:translationIso];
                        [t.languagesDownloading removeObject:translationIso];
                        ps.numDownloaded++;
                        [ps store];
                        if(isCurrentProjectOpen)
                        {
                            [_parentWindow incrementTransByOne];
                        }
                    }
                }
                if(isCurrentProjectOpen)
                {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [_parentWindow reload];
                        [handler setEdited];
                    });
                }
                else
                {
                    [handler storeFileForBackgroundTranslationDownload];
                }
            }
        }
    }
    if((ps.numDownloaded == ps.numToDownload) && ps.isDownloadingTranslations)
    {
        [self endDownload];
        dispatch_async(dispatch_get_main_queue(), ^{
            
            if(isCurrentProjectOpen)
            {
                [_parentWindow finishDownloadingTranslations];
                
                NSAlert* alert = [NSAlert alertWithMessageText:@"Translation Download Complete" defaultButton:@"OK" alternateButton:NULL otherButton:NULL informativeTextWithFormat:@"You have successfully translated phrases for the project: %@.", [_projectPathDir lastPathComponent]];
                [alert runModal];
            }
            else
            {
                NSAlert* alert = [NSAlert alertWithMessageText:@"Translation Download Complete" defaultButton:@"OK" alternateButton:@"Open Project" otherButton:NULL informativeTextWithFormat:@"You have successfully translated phrases for the project: %@.", [_projectPathDir lastPathComponent]];
                NSInteger response = [alert runModal];
                if(response == NSAlertAlternateReturn)
                {
                    [[AppDelegate appDelegate] openProject:_projectPathDir];
                }
                
            }
        });
    }
    return 0;
}

/*
 * Kills the timer for the repeated download function
 * but doesn't stop the download in the project settings or anything.
 * Used when a language window changes to a different project.
 */
- (void)pauseDownload{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_timerTransDownload invalidate];
    });
}

/*
 * Restarts the timer for the download function.
 */
-(void)restartDownload{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(_timerTransDownload)
        {
            [_timerTransDownload invalidate];
        }
        [self getTranslations];
        _timerTransDownload = [NSTimer scheduledTimerWithTimeInterval:downloadRepeatInterval target:self selector:@selector(getTranslations) userInfo:nil repeats:YES];
    });
}

/*
 * Ends the download cleanly in the translation window.
 */
- (void)endDownload{
    _numTransToDownload = 0;
    _latestRequestID = nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [_timerTransDownload invalidate];
    });
    ProjectSettings* ps;
    if(![[AppDelegate appDelegate].projectSettings.projectPath isEqualToString:_projectPath])
    {
        NSMutableDictionary* projectDict = [NSMutableDictionary dictionaryWithContentsOfFile:_projectPath];
        if(projectDict)
        {
            ps = [[ProjectSettings alloc] initWithSerialization:projectDict];
            if(ps)
            {
                ps.projectPath = _projectPath;
                [ps store];
            }
            else
            {
                ps = [[ProjectSettings alloc] init];
            }
        }
        else
        {
            ps = [[ProjectSettings alloc] init];
        }
    }
    else
    {
        ps = [AppDelegate appDelegate].projectSettings;
    }
    ps.isDownloadingTranslations = 0;
    ps.numDownloaded = 0;
    ps.numToDownload = 0;
    [ps store];
    TranslationSettings *translationSettings = [TranslationSettings translationSettings];
    [[translationSettings projectsDownloadingTranslations] removeObject:ps.projectPath];
    [translationSettings updateTranslationSettings];
}

#pragma mark Cancel Download

/*
 * Stops the download after a cancellation request has been sent.
 */
- (void)cancelDownloadWithError:(NSError*)error{
    _numTransToDownload = 0;
    _latestRequestID = nil;
    [_timerTransDownload invalidate];
    ProjectSettings* ps = [AppDelegate appDelegate].projectSettings;
    ps.isDownloadingTranslations = 0;
    ps.numDownloaded = 0;
    ps.numToDownload = 0;
    [ps store];
    TranslationSettings *translationSettings = [TranslationSettings translationSettings];
    [[translationSettings projectsDownloadingTranslations] removeObject:ps.projectPath];
    [translationSettings writeTranslationSettings];
    [self sendCancelNotificationWithError:error];
}

/*
 * Sends cancel notification to the server with an error if there was one
 */
-(void)sendCancelNotificationWithError:(NSError*)error{
    NSDictionary *JSONObject;
    if(error)
    {
        JSONObject = [[NSDictionary alloc] initWithObjectsAndKeys: _guid,@"key",
                                _latestRequestID,@"id",error,@"server_error",nil];
    }
    else
    {
        JSONObject = [[NSDictionary alloc] initWithObjectsAndKeys: _guid,@"key",
                      _latestRequestID,@"id",nil];
    }
    NSError *JSONError;
    NSData *postdata2 = [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:&JSONError];
    NSURL *url = [NSURL URLWithString:cancelURL];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = postdata2;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest: request
                                                                 completionHandler:^(NSData *data,
                                                                                     NSURLResponse *response,
                                                                                     NSError *error)
                                  {
                                      if (!error)
                                      {
                                          NSLog(@"Cancel Status code: %li", ((NSHTTPURLResponse *)response).statusCode);
                                      }
                                      else
                                      {
                                          NSLog(@"Cancel Error: %@", error.localizedDescription);
                                      }
                                  }];
    [task resume];
    _currTask = task;
    
}

#pragma mark Small functions for transaction observer

-(void)saveReceipt:(NSData*)receipt transaction:(SKPaymentTransaction*)transaction{
    [_receipts setObject:receipt forKey:transaction.transactionIdentifier];
}

-(void)setPaymentError{
    [_paymentValidating stopAnimation:self];
    [_translateFromTabView selectTabViewItemAtIndex:paymentErrorIndex];
}

#pragma mark Misc. helper funcs

-(void)cannotFindProjectAlert:(NSString*)projectPath{
    NSAlert* alert = [NSAlert alertWithMessageText:@"Cannot Find Project" defaultButton:@"OK" alternateButton:NULL otherButton:NULL informativeTextWithFormat:@"Could not find the project at %@, which had a pending translation download. If you moved the project, please reopen it and its Language Editor Window and the translation download will begin again. If you deleted it and would like to restart your download, please contact customer support.", projectPath];
    [alert runModal];
}
/*
 * This function uses a ternary operator! Thank you high school computer science!!
 */
- (void)printJSONOrNormalErrorForFunction:(NSString*)functionName JSONError:(NSError*)JSONError Error:(NSError*)error{
    NSLog(@"%@", JSONError ? [NSString stringWithFormat:@"%@ JSONError: %@", functionName, JSONError.localizedDescription] :
          [NSString stringWithFormat:@"%@ Error: %@", functionName, error]);
}

/*
 * Turns off the 'quick edit' option in the languages global dictionary
 * e.g. 'unchecks' them
 */
-(void)uncheckLanguageDict{
    for(LocalizationEditorLanguage* l in [_languages allKeys])
    {
        l.quickEdit = 0;
        for(LocalizationEditorLanguage* l2 in [_languages objectForKey:l])
        {
            l2.quickEdit = 0;
        }
    }
}

/*
 * Disable everything that can be disabled (except buy button since that is handled separately according to
 * availability of a cost estimate, and cancel, since that shouldn't usually/ever be disabled)
 */
-(void)disableAllExceptButtons{
    [_popTranslateFrom setEnabled:0];
    [_languageTable setEnabled:0];
    [_checkAll setEnabled:0];
    [_ignoreText setEnabled:0];
}

/*
 * Disable everything that can be disabled
 */
-(void)disableAll{
    [_popTranslateFrom setEnabled:0];
    [_languageTable setEnabled:0];
    [_checkAll setEnabled:0];
    [_ignoreText setEnabled:0];
    [_cancel setEnabled:0];
    [_buy setEnabled:0];
    NSButton* closeButton = [self.window standardWindowButton:NSWindowCloseButton];
    [closeButton setEnabled:NO];
}

/*
 * Enable everything that can be enabled (except buy button since that is handled separately according to
 * availability of a cost estimate, and cancel, since that shouldn't usually/ever be disabled)
 * Use on main queue because that makes it work.
 */
-(void)enableAllExceptButtons{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_popTranslateFrom setEnabled:YES];
        [_languageTable setEnabled:YES];
        [_checkAll setEnabled:YES];
        [_ignoreText setEnabled:YES];
    });
}

/*
 * Enable everything that can be enabled
 * Use on main queue because that makes it work.
 */
-(void)enableAll{
    dispatch_async(dispatch_get_main_queue(), ^{
        [_popTranslateFrom setEnabled:YES];
        [_languageTable setEnabled:YES];
        [_checkAll setEnabled:YES];
        [_ignoreText setEnabled:YES];
        [_cancel setEnabled:YES];
        [_buy setEnabled:YES];
        NSButton* closeButton = [self.window standardWindowButton:NSWindowCloseButton];
        [closeButton setEnabled:YES];
    });
}

/*
 * Locally format the price of the current translation estimate, display it,
 * and hide the cost downloading message and spinning icon.
 */
-(void)displayPrice{
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [numberFormatter setLocale:_product.priceLocale];
    NSString *formattedString = [numberFormatter stringFromNumber:_product.price];
    _cost.stringValue = formattedString;
    [self enableAllExceptButtons];
    [_costDownloading setHidden:1];
    [_costDownloadingText setHidden:1];
    [_costDownloading stopAnimation:self];
    [_buy setEnabled:1];
}
@end
