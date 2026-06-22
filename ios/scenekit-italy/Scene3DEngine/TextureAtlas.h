#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>
#import <SpriteKit/SpriteKit.h>

@interface TextureAtlas : NSObject

// Named textures
@property (nonatomic, strong, readonly) SKTexture *buildingsTexture;
@property (nonatomic, strong, readonly) SKTexture *roadsTexture;
@property (nonatomic, strong, readonly) SKTexture *terrainTexture;

- (instancetype)initWithBundle:(NSBundle *)bundle;

@end
