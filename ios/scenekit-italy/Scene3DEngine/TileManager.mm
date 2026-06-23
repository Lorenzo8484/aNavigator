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

// Tile key from lat/lon — matches preprocessor format: tile_+LON_LAT.stile
// Uses INTEGER arithmetic to avoid floating-point precision issues
// kTileSizeDeg = 0.01, so we work in centidegrees (×100)
static NSString *TileKey(double lat, double lon) {
    int tileSizeInt = (int)(kTileSizeDeg * 100.0 + 0.5); // 1 centidegree
    int tileLon = (int)(lon * 100.0 + 0.0001); // centidegrees with tiny epsilon
    int tileLat = (int)(lat * 100.0 + 0.0001);
    // Floor to tile grid
    tileLon = (tileLon / tileSizeInt) * tileSizeInt;
    tileLat = (tileLat / tileSizeInt) * tileSizeInt;
    // Format as +LL.LL_+LL.LL (integer parts = /100, fractional = %100)
    return [NSString stringWithFormat:@"%c%d.%02d_%c%d.%02d",
            tileLon >= 0 ? '+' : '-', abs(tileLon) / 100, abs(tileLon) % 100,
            tileLat >= 0 ? '+' : '-', abs(tileLat) / 100, abs(tileLat) % 100];
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

    // Create parent node for this tile — ALL tiles at (0,0,0)
    // because vertices in .stile are in ABSOLUTE scene coordinates
    // (converted from lon/lat/height to east/up/north meters)
    SCNNode *tileNode = [SCNNode node];
    tileNode.name = [NSString stringWithFormat:@"tile_%@", key];
    tileNode.position = SCNVector3Make(0, 0, 0);

    // Add buildings
    for (size_t i = 0; i < tileData.buildings.size(); i++) {
        BuildingData &b = tileData.buildings[i];
        SCNNode *buildingNode = [self createBuildingNode:&b tileCenter:SCNVector3Make(0, 0, 0)];
        if (buildingNode) {
            [tileNode addChildNode:buildingNode];
        }
    }

    // Add roads
    for (size_t i = 0; i < tileData.roads.size(); i++) {
        RoadData &r = tileData.roads[i];
        SCNNode *roadNode = [self createRoadNode:&r tileCenter:SCNVector3Make(0, 0, 0)];
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

    // Version (uint16 — preprocessor uses H format)
    if (offset + 2 > length) return NO;
    uint16_t version = *(const uint16_t *)(bytes + offset);
    offset += 2;
    (void)version;

    // Num buildings (uint32)
    if (offset + 4 > length) return NO;
    uint32_t numBuildings = *(const uint32_t *)(bytes + offset);
    offset += 4;

    // Num roads (uint32)
    if (offset + 4 > length) return NO;
    uint32_t numRoads = *(const uint32_t *)(bytes + offset);
    offset += 4;

    // Has terrain (uint8) — skip
    if (offset + 1 > length) return NO;
    offset += 1;

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

        // colorR, colorG, colorB (uint8 each + 1 padding byte — stored as BBBx)
        if (offset + 4 > length) return NO;
        b.color[0] = (float)bytes[offset] / 255.0f;
        b.color[1] = (float)bytes[offset + 1] / 255.0f;
        b.color[2] = (float)bytes[offset + 2] / 255.0f;
        offset += 4;

        tileData->buildings.push_back(b);
    }

    // Parse roads (numRoads already parsed from header)
    for (uint32_t i = 0; i < numRoads; i++) {
        RoadData r;
        memset(&r, 0, sizeof(r));

        // Road block format (from preprocessor):
        //   centerLat, centerLon (2 floats = 8 bytes)
        //   rtype_len (uint16 = 2 bytes)
        //   rtype_str (variable)
        //   vertex_count (uint32 = 4 bytes)
        //   vertices (vertex_count * 3 * float32)
        //   normals (same count as vertices — no count stored)
        //   indices.size flat count (uint32 = 4 bytes)
        //   indices (flat count * uint32)
        //   color (BBBx = 4 bytes)

        // centerLat (float)
        if (offset + 4 > length) return NO;
        r.centerLat = *(const float *)(bytes + offset);
        offset += 4;

        // centerLon (float)
        if (offset + 4 > length) return NO;
        r.centerLon = *(const float *)(bytes + offset);
        offset += 4;

        // roadTypeLen (uint16)
        if (offset + 2 > length) return NO;
        uint16_t rtype_len = *(const uint16_t *)(bytes + offset);
        offset += 2;

        // roadType string
        if (offset + rtype_len > length) return NO;
        r.roadType = [[NSString alloc] initWithBytes:bytes + offset
                                               length:rtype_len
                                             encoding:NSUTF8StringEncoding];
        offset += rtype_len;

        // vertex_count (uint32)
        if (offset + 4 > length) return NO;
        r.numVertices = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // vertices
        size_t vertsSize = (size_t)r.numVertices * 3 * sizeof(float);
        if (offset + vertsSize > length) return NO;
        r.vertices = (float *)malloc(vertsSize);
        memcpy(r.vertices, bytes + offset, vertsSize);
        offset += vertsSize;

        // normals (same count as vertices — need to calculate)
        if (offset + vertsSize > length) return NO;
        r.normals = (float *)malloc(vertsSize);
        memcpy(r.normals, bytes + offset, vertsSize);
        offset += vertsSize;

        // indices.size flat count (uint32)
        if (offset + 4 > length) return NO;
        r.numIndices = (int)*(const uint32_t *)(bytes + offset);
        offset += 4;

        // indices
        size_t idxSize = (size_t)r.numIndices * sizeof(uint32_t);
        if (offset + idxSize > length) return NO;
        r.indices = (int *)malloc(idxSize);
        memcpy(r.indices, bytes + offset, idxSize);
        offset += idxSize;

        // color (BBBx = 3 uint8 + 1 padding = 4 bytes)
        if (offset + 4 > length) return NO;
        r.color[0] = (float)bytes[offset] / 255.0f;
        r.color[1] = (float)bytes[offset + 1] / 255.0f;
        r.color[2] = (float)bytes[offset + 2] / 255.0f;
        offset += 4;

        tileData->roads.push_back(r);
    }

    return YES;
}

// ---------------------------------------------------------------------------
#pragma mark - Create SceneKit nodes
// ---------------------------------------------------------------------------

- (SCNNode *)createBuildingNode:(BuildingData *)b tileCenter:(SCNVector3)tileCenter {
    if (b->numVertices < 3 || b->numIndices < 3) return nil;

    // Create vertex source — .stile stores (lon, lat, height)
    // Convert to SceneKit (east, up, north) = (x, y, z) in meters from Bologna origin
    SCNVector3 *verts = (SCNVector3 *)malloc((size_t)b->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < b->numVertices; i++) {
        float lon = b->vertices[i * 3];
        float lat = b->vertices[i * 3 + 1];
        float height = b->vertices[i * 3 + 2];
        double latRad = lat * M_PI / 180.0;
        float x = (float)((lon - kOriginLon) * kMetersPerDegreeLat * cos(latRad));
        float y = height; // height is already in meters
        float z = (float)((lat - kOriginLat) * kMetersPerDegreeLat);
        verts[i] = SCNVector3Make(x, y, z);
    }
    SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithVertices:verts
                                                                              count:b->numVertices];

    // Create normal source — .stile normals are (nx_lon, ny_lat, nz_height)
    // Convert to SceneKit: (nx_lon, nz_height, ny_lat) → (x_east, y_up, z_north)
    SCNVector3 *norms = (SCNVector3 *)malloc((size_t)b->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < b->numVertices; i++) {
        norms[i] = SCNVector3Make(b->normals[i * 3],       // nx → x (east/lon direction)
                                  b->normals[i * 3 + 2],   // nz → y (up/height direction)
                                  b->normals[i * 3 + 1]);  // ny → z (north/lat direction)
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

    // Create vertex source — .stile stores (lon, lat, height)
    // Convert to SceneKit (east, up, north) = (x, y, z) in meters from Bologna origin
    SCNVector3 *verts = (SCNVector3 *)malloc((size_t)r->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < r->numVertices; i++) {
        float lon = r->vertices[i * 3];
        float lat = r->vertices[i * 3 + 1];
        float height = r->vertices[i * 3 + 2];
        double latRad = lat * M_PI / 180.0;
        float x = (float)((lon - kOriginLon) * kMetersPerDegreeLat * cos(latRad));
        float y = height;
        float z = (float)((lat - kOriginLat) * kMetersPerDegreeLat);
        verts[i] = SCNVector3Make(x, y, z);
    }
    SCNGeometrySource *vertexSource = [SCNGeometrySource geometrySourceWithVertices:verts
                                                                              count:r->numVertices];

    // Create normal source — .stile normals are (nx_lon, ny_lat, nz_height)
    SCNVector3 *norms = (SCNVector3 *)malloc((size_t)r->numVertices * sizeof(SCNVector3));
    for (int i = 0; i < r->numVertices; i++) {
        norms[i] = SCNVector3Make(r->normals[i * 3],       // nx → x (east)
                                  r->normals[i * 3 + 2],   // nz → y (up)
                                  r->normals[i * 3 + 1]);  // ny → z (north)
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
    // Use centidegree integer math to avoid FP precision issues
    int tileSizeInt = (int)(kTileSizeDeg * 100.0 + 0.5); // 1 centidegree
    int centerTileLatCD = (int)(lat * 100.0 + 0.0001); // centidegrees with epsilon
    int centerTileLonCD = (int)(lon * 100.0 + 0.0001);
    // Floor to tile grid
    centerTileLatCD = (centerTileLatCD / tileSizeInt) * tileSizeInt;
    centerTileLonCD = (centerTileLonCD / tileSizeInt) * tileSizeInt;

    // Load tiles within 3-tile radius
    NSMutableSet<NSString *> *neededKeys = [NSMutableSet set];
    for (int dy = -3; dy <= 3; dy++) {
        for (int dx = -3; dx <= 3; dx++) {
            int tileLatCD = centerTileLatCD + dy * tileSizeInt;
            int tileLonCD = centerTileLonCD + dx * tileSizeInt;
            // Format as +LL.LL_+LL.LL to match TileKey
            NSString *key = [NSString stringWithFormat:@"%c%d.%02d_%c%d.%02d",
                             tileLonCD >= 0 ? '+' : '-', abs(tileLonCD) / 100, abs(tileLonCD) % 100,
                             tileLatCD >= 0 ? '+' : '-', abs(tileLatCD) / 100, abs(tileLatCD) % 100];
            [neededKeys addObject:key];
        }
    }

    // Unload tiles outside 4-tile radius
    int unloadRadius = 4;
    NSMutableSet<NSString *> *toUnload = [NSMutableSet set];
    int unloadRadiusCD = unloadRadius * tileSizeInt;
    for (NSString *key in self.loadedTiles) {
        // Parse key format "+LL.LL_+LL.LL" to centidegrees
        // Example: "+11.34_+44.49" → lonCD=1134, latCD=4449
        int lonCD = 0, latCD = 0;
        int intPart = 0, fracPart = 0;
        char sign = '+';
        NSScanner *sc = [NSScanner scannerWithString:key];
        [sc scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"+-"] intoString:NULL];
        if ([sc scanInt:&intPart] && [sc scanString:@"." intoString:NULL] && [sc scanInt:&fracPart]) {
            lonCD = intPart * 100 + fracPart;
            if (sign == '-') lonCD = -lonCD;
        }
        [sc scanString:@"_" intoString:NULL];
        sign = '+';
        [sc scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"+-"] intoString:NULL];
        if ([sc scanInt:&intPart] && [sc scanString:@"." intoString:NULL] && [sc scanInt:&fracPart]) {
            latCD = intPart * 100 + fracPart;
            if (sign == '-') latCD = -latCD;
        }

        if (abs(lonCD - centerTileLonCD) > unloadRadiusCD ||
            abs(latCD - centerTileLatCD) > unloadRadiusCD) {
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

        // Parse key to centidegrees: "+LL.LL_+LL.LL" → (lonCD, latCD)
        int lonCD = 0, latCD = 0;
        int intPart = 0, fracPart = 0;
        char sign = '+';
        NSScanner *sc = [NSScanner scannerWithString:key];
        [sc scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"+-"] intoString:NULL];
        if ([sc scanInt:&intPart] && [sc scanString:@"." intoString:NULL] && [sc scanInt:&fracPart]) {
            lonCD = intPart * 100 + fracPart;
            if (sign == '-') lonCD = -lonCD;
        }
        [sc scanString:@"_" intoString:NULL];
        sign = '+';
        [sc scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"+-"] intoString:NULL];
        if ([sc scanInt:&intPart] && [sc scanString:@"." intoString:NULL] && [sc scanInt:&fracPart]) {
            latCD = intPart * 100 + fracPart;
            if (sign == '-') latCD = -latCD;
        }

        // Convert centidegrees back to double for loadTileAtLat:lon:
        // Use safe division (divide by 100.0, not by 0.01) to avoid FP drift
        double tileLat = (double)latCD / 100.0;
        double tileLon = (double)lonCD / 100.0;
        [self loadTileAtLat:tileLat lon:tileLon];
    }
}

@end
