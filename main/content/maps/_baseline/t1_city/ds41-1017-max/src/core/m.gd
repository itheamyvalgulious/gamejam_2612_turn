## Material id table shared by GDScript + shaders (keep in sync with gfx/surface.gdshader).
class_name M
extends RefCounted

const WALL := 0
const GLASS := 1
const METAL := 2
const WOOD := 3
const FABRIC := 4
const TILE := 5
const ASPHALT := 6
const CONCRETE := 7
const EMIT := 8
const SCREEN := 9
const CERAMIC := 10
const FOLIAGE := 11
const SOIL := 12
const RUBBER := 13
const PLASTIC := 14
const ROADPAINT := 15

# wall styles (par.w in shader when mat == WALL)
const STY_PUNCHED := 0.0
const STY_CURTAIN := 1.0
const STY_BRICK := 2.0
const STY_PANEL := 3.0
const STY_RIBBON := 4.0
const STY_FINS := 5.0
const STY_INDUSTRIAL := 6.0
const STY_SHOPFRONT := 7.0