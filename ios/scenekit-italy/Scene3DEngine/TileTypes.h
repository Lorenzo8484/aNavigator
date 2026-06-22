#import <Foundation/Foundation.h>
#import <simd/simd.h>
#import <vector>

// -- Building vertex data ---------------------------------------------------

typedef struct {
    float centerLat;
    float centerLon;
    float *vertices;       // 3 floats per vertex (x, y, z)
    float *normals;        // 3 floats per normal (nx, ny, nz)
    int   *indices;        // triangle indices
    float color[3];        // RGB 0..1
    int   numVertices;
    int   numIndices;
} BuildingData;

// -- Road vertex data -------------------------------------------------------

typedef struct {
    float centerLat;
    float centerLon;
    float *vertices;       // 3 floats per vertex
    float *normals;        // 3 floats per normal
    int   *indices;        // triangle indices
    float color[3];        // RGB 0..1
    int   numVertices;
    int   numIndices;
    NSString *roadType;    // e.g. @"primary", @"residential"
} RoadData;

// -- Tile data container ----------------------------------------------------

typedef struct {
    std::vector<BuildingData> buildings;
    std::vector<RoadData> roads;
} TileData;

// -- Helpers to free tile data memory ---------------------------------------

static inline void FreeBuildingData(BuildingData *b) {
    if (b->vertices)  free(b->vertices);
    if (b->normals)   free(b->normals);
    if (b->indices)   free(b->indices);
    b->vertices  = NULL;
    b->normals   = NULL;
    b->indices   = NULL;
    b->numVertices = 0;
    b->numIndices  = 0;
}

static inline void FreeRoadData(RoadData *r) {
    if (r->vertices)  free(r->vertices);
    if (r->normals)   free(r->normals);
    if (r->indices)   free(r->indices);
    r->vertices  = NULL;
    r->normals   = NULL;
    r->indices   = NULL;
    r->numVertices = 0;
    r->numIndices  = 0;
    r->roadType = nil;
}

static inline void FreeTileData(TileData *t) {
    for (auto &b : t->buildings) FreeBuildingData(&b);
    for (auto &r : t->roads)     FreeRoadData(&r);
    t->buildings.clear();
    t->roads.clear();
}
