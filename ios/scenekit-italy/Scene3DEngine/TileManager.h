#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

@interface TileManager : NSObject

- (instancetype)initWithScene:(SCNScene *)scene;

// Load a tile at the given lat/lon (tile space center)
- (SCNNode *)loadTileAtLat:(double)lat lon:(double)lon;

// Unload a tile from the scene
- (void)unloadTileAtLat:(double)lat lon:(double)lon;

// Update tile set for a given location: load tiles within 3-tile radius,
// unload tiles outside 4-tile radius.
- (void)updateForLocation:(double)lat lon:(double)lon;

@end
