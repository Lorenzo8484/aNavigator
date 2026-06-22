#import "TextureAtlas.h"

@implementation TextureAtlas

- (instancetype)initWithBundle:(NSBundle *)bundle {
    self = [super init];
    if (self) {
        if (!bundle) bundle = [NSBundle mainBundle];

        // Load textures from bundle
        UIImage *buildingsImg = [UIImage imageNamed:@"buildings_atlas_4k" inBundle:bundle compatibleWithTraitCollection:nil];
        if (!buildingsImg) {
            // Try loading from textures subdirectory
            NSString *path = [bundle pathForResource:@"buildings_atlas_4k" ofType:@"png" inDirectory:@"textures"];
            if (!path) path = [bundle pathForResource:@"buildings_atlas_4k" ofType:@"png"];
            if (path) buildingsImg = [UIImage imageWithContentsOfFile:path];
        }
        if (buildingsImg) {
            _buildingsTexture = [SKTexture textureWithImage:buildingsImg];
        }

        UIImage *roadsImg = [UIImage imageNamed:@"roads_atlas_4k" inBundle:bundle compatibleWithTraitCollection:nil];
        if (!roadsImg) {
            NSString *path = [bundle pathForResource:@"roads_atlas_4k" ofType:@"png" inDirectory:@"textures"];
            if (!path) path = [bundle pathForResource:@"roads_atlas_4k" ofType:@"png"];
            if (path) roadsImg = [UIImage imageWithContentsOfFile:path];
        }
        if (roadsImg) {
            _roadsTexture = [SKTexture textureWithImage:roadsImg];
        }

        UIImage *terrainImg = [UIImage imageNamed:@"terrain_atlas_4k" inBundle:bundle compatibleWithTraitCollection:nil];
        if (!terrainImg) {
            NSString *path = [bundle pathForResource:@"terrain_atlas_4k" ofType:@"png" inDirectory:@"textures"];
            if (!path) path = [bundle pathForResource:@"terrain_atlas_4k" ofType:@"png"];
            if (path) terrainImg = [UIImage imageWithContentsOfFile:path];
        }
        if (terrainImg) {
            _terrainTexture = [SKTexture textureWithImage:terrainImg];
        }
    }
    return self;
}

@end
