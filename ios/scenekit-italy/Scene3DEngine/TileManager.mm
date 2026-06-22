#import "TileManager.h"
#import "TileTypes.h"
#import <SceneKit/SceneKit.h>
#import <vector>
#import <map>
#import <string>
#import <cmath>

// Tile size in degrees (must match preprocessor: 0.01° ≈ 1 km)
static const double kTileSizeDeg = 0.01;

// Conversion constants
static const double kMetersPerDegreeLat = 111320.0;

// Bologna origin
static const double kOriginLat = 44.49;
static const double kOriginLon = 11.34;

// ---------------------------------------------------------------------------
@interface TileManager ()

@property (nonatomic, weak) SCNScene *scene;
@property (nonatomic, strong) NSMutableDictionary<NSString *, SCNNode *> *loadedTiles;

@end

// ---------------------------------------------------------------------------
#pragma mark - Helpers
// ---------------------------------------------------------------------------

// Tile key from lat/lon
static NSString *TileKey(double lat, double lon) {
    int tileLat = (int)floor(lat / kTileSizeDeg);
    int tileLon = (int)floor(lon / kTileSizeDeg);
    return [NSString stringWithFormat:@"%+03d_%+04d", tileLon, tileLat];
}

// Scene coordinate conversion
static SCNVector3 SceneCoord(double lat, double lon, double alt) {
    double latRad = lat * M_PI / 180.0;
    double x = (lon - kOriginLon) * kMetersPerDegreeLat * cos(latRad);
    double z = (lat - kOriginLat) * kMetersPerDegreeLat;
    return SCNVector3Make((float)x, (float)alt, (float)z);
}

// ---------------------------------------------------------------------------
#pragma mark - Implementation
// ---------------------------------------------------------------------------

@implementation TileManager

- (instancetype)initWithScene:(SCNScene *)scene {
    self = [super init];
    if (self) {
        _scene = scene;
        _loadedTiles = [NSMutableDictionary dictionary];
    }
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Load tile
// ---------------------------------------------------------------------------

- (SCNNode *)loadTileAtLat:(double)lat lon:(double)lon {
    NSString *key = TileKey(lat, lon);
    if (self.loadedTiles[key]) {
        return self.loadedTiles[key]; // already loaded
    }

    // Build file path - try bundle first
    NSString *filename = [NSString stringWithFormat:@"tile_%@.stile", key];
    NSString *bundlePath = [[NSBundle mainBundle] pathForResource:[filename stringByDeletingPathExtension]
                                                           ofType:@"stile"];
    if (!bundlePath) {
        // Try tiles directory
        bundlePath = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:@"tiles"];
    }
    if (!bundlePath) {
        // Try data/tiles directory
        bundlePath = [[NSBundle mainBundle] pathForResource:filename ofType:nil inDirectory:@"data/tiles"];
    }
    if (!bundlePath) {
        // Silently skip missing tiles
        return nil;
    }

    // Read file data
    NSData *fileData = [NSData dataWithContentsOfFile:bundlePath];
    if (!fileData || fileData.length < 8) {
        return nil;
    }

    // Parse .stile binary format
    TileData tileData;
    if (![self parseStileData:fileData intoTileData:&tileData]) {
        return nil;
    }

    // Create parent node for this tile
    SCNNode *tileNode = [SCNNode node];
    tileNode.name = [NSString stringWithFormat:@"tile_%@", key];

    // Compute tile center in scene coordinates
    double tileCenterLat = (floor(lat / kTileSizeDeg) + 0.5) * kTileSizeDeg;
    double tileCenterLon = (floor(lon / kTileSizeDeg) + 0.5) * kTileSizeDeg;
    SCNVector3 tileSceneCenter = SceneCoord(tileCenterLat, tileCenterLon, 0);
    tileNode.position = tileSceneCenter;

    // Add buildings
    for (size_t i = 0; i < tileData.buildings.size(); i++) {
        BuildingData &b = tileData.buildings[i];
        SCNNode *buildingNode = [self createBuildingNode:&b tileCenter:tileSceneCenter];
        if (buildingNode) {
            [tileNode addChildNode:buildingNode];
        }
    }

    // Add roads
    for (size_t i = 0; i < tileData.roads.size(); i++) {
        RoadData &r = tileData.roads[i];
        SCNNode *roadNode = [self createRoadNode:&r tileCenter:tileSceneCenter];
        if (roadNode) {
            [tileNode addChildNode:roadNode];
        }
    }

    // Free parsed data
    FreeTileData(&tileData);

    // Add to scene
    [self.scene.rootNode addChildNode:tileNode];
    self.loadedTiles[key] = tileNode;

    return tileNode;
}

// ---------------------------------------------------------------------------
#pragma mark - .stile parser
// ---------------------------------------------------------------------------

- (BOOL)parseStileData:(NSData *)data intoTileData:(TileData *)tileData {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    NSUInteger length = data.length;
    NSUInteger offset = 0;

    // Magic: "STIL"
    if (offset + 4 > length) return NO;
    if (bytes[0] != 'S' || bytes[1] != 'T' || bytes[2] != 'I' || bytes[3] != 'L') {
        return NO;
    }
    offset += 4;

    // Version (uint32)
    if (offset + 4 > length) return NO;
    uint32_t version = *(const uint32_t *)(bytes + offset);
    offset += 4;
    (void)version; // unused for now

    // Num buildings (uint32)
    if (offset + 4 > length) return NO;
    uint32_t numBuildings = *(const uint32_t *)(bytes + offset);
    offset += 4;

    // Parse buildings
    for (uint32_t i = 0; i < numBuildings; i++) {
        BuildingData b;
        memset(&b, 0, sizeof(b));

        // centerLat (float)
        if (offset + 4 > length) return NO;
        b.centerLat = *(const float *)(bytes + offset);
        offset += 4;

        // centerLon (float)
        if (offset + 4 > length) return NO;
        b.centerLon = *(const float *)(bytes + offset);
        offset += 4;

        // numVerts (uint32)
        if (offset + 4 > length) return NO;
        b.numVertices = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // vertices (float * 3 * numVerts)
        size_t vertsSize = (size_t)b.numVertices * 3 * sizeof(float);
        if (offset + vertsSize > length) return NO;
        b.vertices = (float *)malloc(vertsSize);
        memcpy(b.vertices, bytes + offset, vertsSize);
        offset += vertsSize;

        // numNormals (uint32)
        if (offset + 4 > length) return NO;
        int numNormals = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // normals (float * 3 * numNormals)
        size_t normsSize = (size_t)numNormals * 3 * sizeof(float);
        if (offset + normsSize > length) return NO;
        b.normals = (float *)malloc(normsSize);
        memcpy(b.normals, bytes + offset, normsSize);
        offset += normsSize;

        // numIndices (uint32)
        if (offset + 4 > length) return NO;
        b.numIndices = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // indices (uint32 * numIndices)
        size_t idxSize = (size_t)b.numIndices * sizeof(uint32_t);
        if (offset + idxSize > length) return NO;
        b.indices = (int *)malloc(idxSize);
        memcpy(b.indices, bytes + offset, idxSize);
        offset += idxSize;

        // colorR, colorG, colorB (float each)
        if (offset + 12 > length) return NO;
        b.color[0] = *(const float *)(bytes + offset);
        b.color[1] = *(const float *)(bytes + offset + 4);
        b.color[2] = *(const float *)(bytes + offset + 8);
        offset += 12;

        tileData->buildings.push_back(b);
    }

    // Num roads (uint32)
    if (offset + 4 > length) return NO;
    uint32_t numRoads = *(const uint32_t *)(bytes + offset);
    offset += 4;

    // Parse roads
    for (uint32_t i = 0; i < numRoads; i++) {
        RoadData r;
        memset(&r, 0, sizeof(r));

        // centerLat (float)
        if (offset + 4 > length) return NO;
        r.centerLat = *(const float *)(bytes + offset);
        offset += 4;

        // centerLon (float)
        if (offset + 4 > length) return NO;
        r.centerLon = *(const float *)(bytes + offset);
        offset += 4;

        // numVerts (uint32)
        if (offset + 4 > length) return NO;
        r.numVertices = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // vertices
        size_t vertsSize = (size_t)r.numVertices * 3 * sizeof(float);
        if (offset + vertsSize > length) return NO;
        r.vertices = (float *)malloc(vertsSize);
        memcpy(r.vertices, bytes + offset, vertsSize);
        offset += vertsSize;

        // numNormals (uint32)
        if (offset + 4 > length) return NO;
        int numNormals = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // normals
        size_t normsSize = (size_t)numNormals * 3 * sizeof(float);
        if (offset + normsSize > length) return NO;
        r.normals = (float *)malloc(normsSize);
        memcpy(r.normals, bytes + offset, normsSize);
        offset += normsSize;

        // numIndices (uint32)
        if (offset + 4 > length) return NO;
        r.numIndices = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // indices
        size_t idxSize = (size_t)r.numIndices * sizeof(uint32_t);
        if (offset + idxSize > length) return NO;
        r.indices = (int *)malloc(idxSize);
        memcpy(r.indices, bytes + offset, idxSize);
        offset += idxSize;

        // colorR, colorG, colorB (float each)
        if (offset + 12 > length) return NO;
        r.color[0] = *(const float *)(bytes + offset);
        r.color[1] = *(const float *)(bytes + offset + 4);
        r.color[2] = *(const float *)(bytes + offset + 8);
        offset += 12;

        // roadTypeLen (uint32)
        if (offset + 4 > length) return NO;
        uint32_t roadTypeLen = *(const uint32_t *)(bytes + offset);
        offset += 4;

        // roadType (char * roadTypeLen)
        if (offset + roadTypeLen > length) return NO;
        r.roadType = [[NSString alloc] initWithBytes:bytes + offset
                                               length:roadTypeLen
                                             encoding:NSUTF8StringEncoding];
        offset += roadTypeLen;

        tileData->roads.push_back(r);
    }

    return YES;
}

// ---------------------------------------------------------------------------
#pragma mark - Create SceneKit nodes
// ---------------------------------------------------------------------------

- (SCNNode *)createBuildingNode:(BuildingData *)b tileCenter:(SCNVector3)tileCenter {
    if (b->numVertices < 3 || b->numIndices < 3) return nil;

    // Create vertex source
    SCNVector3 *verts = (SCNVector3 *)malloc((size_t)b->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < b->numVertices; i++) {
        verts[i] = SCNVector3Make(b->vertices[i * 3],
                                  b->vertices[i * 3 + 1],
                                  b->vertices[i * 3 + 2]);
    }
    SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithVertices:verts
                                                                              count:b->numVertices];

    // Create normal source
    SCNVector3 *norms = (SCNVector3 *)malloc((size_t)b->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < b->numVertices; i++) {
        norms[i] = SCNVector3Make(b->normals[i * 3],
                                  b->normals[i * 3 + 1],
                                  b->normals[i * 3 + 2]);
    }
    SCNGeometrySource *normalSource = [SCNGeometrySource geometrySourceWithNormals:norms
                                                                             count:b->numVertices];

    // Create element (indices)
    // The indices in .stile are uint32. SCNGeometryElement expects CInt (int32).
    NSData *idxData = [NSData dataWithBytes:b->indices length:(NSUInteger)b->numIndices * sizeof(int)];
    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:idxData
                                                                       primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                                      primitiveCount:b->numIndices / 3
                                                                       bytesPerIndex:sizeof(int)];

    // Create geometry
    SCNGeometry *geometry = [SCNGeometry geometryWithSources:@[vertexSource, normalSource]
                                                     elements:@[element]];

    // Create material
    SCNMaterial *material = [SCNMaterial material];
    material.diffuse.contents = [UIColor colorWithRed:(CGFloat)b->color[0]
                                                green:(CGFloat)b->color[1]
                                                 blue:(CGFloat)b->color[2]
                                                alpha:1.0];
    material.lightingModelName = SCNLightingModelLambert;
    material.doubleSided = NO;
    geometry.materials = @[material];

    // Create node
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    node.castsShadow = YES;

    free(verts);
    free(norms);

    return node;
}

- (SCNNode *)createRoadNode:(RoadData *)r tileCenter:(SCNVector3)tileCenter {
    if (r->numVertices < 3 || r->numIndices < 3) return nil;

    // Create vertex source
    SCNVector3 *verts = (SCNVector3 *)malloc((size_t)r->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < r->numVertices; i++) {
        verts[i] = SCNVector3Make(r->vertices[i * 3],
                                  r->vertices[i * 3 + 1],
                                  r->vertices[i * 3 + 2]);
    }
    SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithVertices:verts
                                                                              count:r->numVertices];

    // Create normal source
    SCNVector3 *norms = (SCNVector3 *)malloc((size_t)r->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < r->numVertices; i++) {
        norms[i] = SCNVector3Make(r->normals[i * 3],
                                  r->normals[i * 3 + 1],
                                  r->normals[i * 3 + 2]);
    }
    SCNGeometrySource *normalSource = [SCNGeometrySource geometrySourceWithNormals:norms
                                                                             count:r->numVertices];

    // Create element
    NSData *idxData = [NSData dataWithBytes:r->indices length:(NSUInteger)r->numIndices * sizeof(int)];
    SCNGeometryElement *element = [SCNGeometryElement geometryElementWithData:idxData
                                                                       primitiveType:SCNGeometryPrimitiveTypeTriangles
                                                                      primitiveCount:r->numIndices / 3
                                                                       bytesPerIndex:sizeof(int)];

    // Create geometry
    SCNGeometry *geometry = [SCNGeometry geometryWithSources:@[vertexSource, normalSource]
                                                     elements:@[element]];

    // Create material - asphalt color
    SCNMaterial *material = [SCNMaterial material];
    material.diffuse.contents = [UIColor colorWithRed:(CGFloat)r->color[0]
                                                green:(CGFloat)r->color[1]
                                                 blue:(CGFloat)r->color[2]
                                                alpha:1.0];
    material.lightingModelName = SCNLightingModelLambert;
    material.doubleSided = NO;
    geometry.materials = @[material];

    // Create node
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    node.castsShadow = NO; // roads don't cast shadows

    free(verts);
    free(norms);

    return node;
}

// ---------------------------------------------------------------------------
#pragma mark - Unload tile
// ---------------------------------------------------------------------------

- (void)unloadTileAtLat:(double)lat lon:(double)lon {
    NSString *key = TileKey(lat, lon);
    SCNNode *tileNode = self.loadedTiles[key];
    if (!tileNode) return;

    [tileNode removeFromParentNode];
    [self.loadedTiles removeObjectForKey:key];
}

// ---------------------------------------------------------------------------
#pragma mark - Update for location
// ---------------------------------------------------------------------------

- (void)updateForLocation:(double)lat lon:(double)lon {
    int centerTileLat = (int)floor(lat / kTileSizeDeg);
    int centerTileLon = (int)floor(lon / kTileSizeDeg);

    // Tile degrees for the center tile
    double centerLatDeg = centerTileLat * kTileSizeDeg;
    double centerLonDeg = centerTileLon * kTileSizeDeg;

    // Load tiles within 3-tile radius
    NSMutableSet<NSString *> *neededKeys = [NSMutableSet set];
    for (int dy = -3; dy <= 3; dy++) {
        for (int dx = -3; dx <= 3; dx++) {
            double tileLat = centerLatDeg + (dy + 0.5) * kTileSizeDeg;
            double tileLon = centerLonDeg + (dx + 0.5) * kTileSizeDeg;
            NSString *key = TileKey(tileLat, tileLon);
            [neededKeys addObject:key];
        }
    }

    // Unload tiles outside 4-tile radius
    int unloadRadius = 4;
    NSMutableSet<NSString *> *toUnload = [NSMutableSet set];
    for (NSString *key in self.loadedTiles) {
        // Parse key to get tile coords
        NSScanner *scanner = [NSScanner scannerWithString:key];
        int lonTile, latTile;
        [scanner scanInt:&lonTile];
        [scanner scanString:@"_" intoString:nil];
        [scanner scanInt:&latTile];

        if (abs(lonTile - centerTileLon) > unloadRadius ||
            abs(latTile - centerTileLat) > unloadRadius) {
            [toUnload addObject:key];
        }
    }

    // Unload
    for (NSString *key in toUnload) {
        SCNNode *node = self.loadedTiles[key];
        [node removeFromParentNode];
        [self.loadedTiles removeObjectForKey:key];
    }

    // Load needed tiles
    for (NSString *key in neededKeys) {
        if (self.loadedTiles[key]) continue;

        // Parse key
        NSScanner *scanner = [NSScanner scannerWithString:key];
        int lonTile, latTile;
        [scanner scanInt:&lonTile];
        [scanner scanString:@"_" intoString:nil];
        [scanner scanInt:&latTile];

        double tileLat = latTile * kTileSizeDeg + kTileSizeDeg * 0.5;
        double tileLon = lonTile * kTileSizeDeg + kTileSizeDeg * 0.5;

        [self loadTileAtLat:tileLat lon:tileLon];
    }
}

@end
