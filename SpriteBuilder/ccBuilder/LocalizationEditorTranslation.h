//
//  LocalizationEditorTranslation.h
//  SpriteBuilder
//
//  Created by Viktor on 8/7/13.
//
//

#import <Foundation/Foundation.h>

@interface LocalizationEditorTranslation : NSObject <NSPasteboardWriting>
{
    NSMutableDictionary* _translations;
    NSMutableArray* _languagesDownloading;
}

- (id) initWithSerialization:(id)ser;

@property (nonatomic,copy) NSString* key;
@property (nonatomic,copy) NSString* comment;
@property (nonatomic,strong) NSMutableArray* languagesDownloading;
@property (nonatomic,readonly) NSMutableDictionary* translations;

- (BOOL) hasTranslationsForLanguages:(NSArray*)languages;
- (id) serialization;

@end
