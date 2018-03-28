module Layer.FSS exposing
    ( Config
    , Mesh
    , SerializedScene
    , makeEntity
    , build
    , init
    )

import Array

import Math.Matrix4 as Mat4 exposing (Mat4)
import Math.Vector2 as Vec2 exposing (vec2, Vec2)
import Math.Vector3 as Vec3 exposing (vec3, Vec3, getX, getY, getZ)
import Math.Vector4 as Vec4 exposing (vec4, Vec4)
import WebGL
import WebGL.Settings exposing (Setting)
import Time exposing (Time)
import Mouse exposing (Position)

import Viewport exposing (Viewport)


type alias Config = {}


type alias Mesh = WebGL.Mesh Vertex


-- Serialization


type alias SColor =
    { rgba : List Float
    , hex : String
    , opacity : Float
    }


type alias SLight =
    { ambient : SColor
    , diffuse : SColor
    , position : List Float
    , ray : List Float
    }


type alias SMaterial =
    { ambient : SColor
    , diffuse : SColor
    , slave : SColor
    }


type alias SPlane =
    { width : Int
    , height : Int
    , triangles : List STriangle
    , vertices : List SVertex
    , segmentWidth : Int
    , sliceHeight : Int
    }


type alias SSide = Float


type alias STriangle =
    { a : SVertex
    , b : SVertex
    , c : SVertex
    , centroid : List Float
    , color : SColor
    , normal : List Float
    , u : List Float
    , v : List Float
    , vertices : List SVertex
    }


type alias SVertex =
    { position : List Float
    , velocity : List Float
    , anchor : List Float
    , time : Float
    , gradient : Float
    }


type alias SMesh =
    { geometry : SPlane
    , material : SMaterial
    , position : List Float
    , side : SSide
    --, depth : Int
    }


type alias SerializedScene =
    { lights : List SLight
    , meshes : List SMesh
    }


-- Base logic

init : Config
init = {}


makeEntity : Viewport {} -> Time -> ( Vec2, Vec2 ) -> Maybe SerializedScene -> List Setting -> Mesh -> WebGL.Entity
makeEntity viewport now mouseDir maybeScene settings mesh =
    let
        lights = maybeScene
            |> Maybe.map (\scene -> scene.lights)
            |> Maybe.withDefault []
        size = maybeScene
            |> Maybe.map (\scene ->
                List.head scene.meshes )
            |> Maybe.map (\maybeMesh ->
                case maybeMesh of
                    Just mesh -> ( mesh.geometry.width,  mesh.geometry.height )
                    Nothing -> (0, 0)
                )
            |> Maybe.withDefault (0, 0)
    in
        WebGL.entityWith
            settings
            vertexShader
            fragmentShader
            mesh
            (uniforms viewport now size mouseDir lights)


-- Mesh


type alias Vertex =
    { aAmbient : Vec4
    , aDiffuse : Vec4
    , aCentroid : Vec3
    , aNormal : Vec3
    , aPosition : Vec3
    , aSide : Float
    , aColor : Vec4
    , aVelocity : Vec3
    , aPhi : Float
    }


defaultVertex : Vertex
defaultVertex =
    { aAmbient = vec4 0 0 0 0
    , aCentroid = vec3 0 0 0
    , aDiffuse = vec4 0 0 0 0
    , aNormal = vec3 0 0 0
    , aPosition = vec3 0 0 0
    , aSide = 0
    , aColor = vec4 0 0 0 0
    , aVelocity = vec3 0 0 0
    , aPhi = 0
    }


build : Config -> Maybe SerializedScene -> Mesh
build config maybeScene =
    WebGL.triangles
        (maybeScene
            |> Maybe.map (\scene ->
                case List.head scene.meshes of
                    Just mesh ->
                        let
                            triangle =
                                ( quickVertex (vec3 0 0 0)
                                , quickVertex (vec3 1 1 0)
                                , quickVertex (vec3 1 -1 0)
                                )
                            convertedTriangles  = convertTriangles
                                                      mesh.material
                                                      mesh.side
                                                      mesh.geometry.triangles


                        in
                            convertedTriangles
                            --(Debug.log "triangles" [ triangle ])
                    Nothing -> []
            )
            |> Maybe.withDefault [ ])




quickVertex : Vec3 -> Vertex
quickVertex pos =
    { defaultVertex | aPosition = pos }


convertTriangles :  SMaterial -> SSide -> List STriangle -> List ( Vertex, Vertex, Vertex )
convertTriangles material side src =
    src |>
        List.indexedMap
            (\index sTriangle ->
                case sTriangle.vertices of
                    a::b::c::_ ->
                        ( a |> convertVertex (vec4 a.gradient a.gradient a.gradient 1) material sTriangle side
                        , b |> convertVertex (vec4 b.gradient b.gradient b.gradient 1) material sTriangle side
                        , c |> convertVertex (vec4  c.gradient c.gradient c.gradient 1) material sTriangle side
                        )

                    _ ->
                        ( defaultVertex
                        , defaultVertex
                        , defaultVertex
                        )
            )


convertVertex : Vec4 -> SMaterial -> STriangle -> SSide -> SVertex -> Vertex
convertVertex color material triangle side v =
    { aSide = side
    , aAmbient = v4fromList material.ambient.rgba
    , aDiffuse = v4fromList material.diffuse.rgba
    , aPosition = v3fromList v.position -- |> adaptPosition size
    , aCentroid = v3fromList triangle.centroid
    , aNormal = v3fromList triangle.normal
    , aColor = color
    , aVelocity = v3fromList v.velocity
    , aPhi = v.time
    }




v3fromList : List Float -> Vec3
v3fromList list =
    case list of
        a::b::c::_ -> vec3 a b c
        a::b::_ -> vec3 a b 0
        [a] -> vec3 a 0 0
        _ -> vec3 0 0 0


v4fromList : List Float -> Vec4
v4fromList list =
    case list of
        a::b::c::d::_ -> vec4 a b c d
        a::b::c::_ -> vec4 a b c 0
        a::b::_ -> vec4 a b 0 0
        [a] -> vec4 a 0 0 0
        _ -> vec4 0 0 0 0


-- Shaders


type alias Uniforms =
    Viewport
        { uResolution : Vec3
        , uLightPosition : Mat4
        , uLightAmbient : Mat4
        , uLightDiffuse : Mat4
        , uResolution : Vec3
        , uNow : Float
        , uSegment : Vec3
        }


uniforms : Viewport {} -> Time -> (Int, Int) -> (Vec2, Vec2) -> List SLight -> Uniforms
uniforms v now size mouseDir lights =
    let
        adaptedLights = lights |> adaptLights size
        width = Vec2.getX v.size
        height = Vec2.getY v.size
        depth = 100.0
      --  ff = Debug.log "mouseDir" mouseDir
    in
        -- { perspective = Mat4.mul v.perspective v.camera }
        { uResolution = vec3 width height depth

        , uLightAmbient = adaptedLights.ambient
        , uLightDiffuse = adaptedLights.diffuse
        , uLightPosition = adaptedLights.position
        , uNow = now
        , uSegment  = vec3 100 100 50

        , rotation = v.rotation
        , perspective = v.perspective
        , camera = v.camera
        --, shade = 0.8
        , cameraTranslate = v.cameraTranslate
        , cameraRotate = v.cameraRotate

        , size = v.size
        }


type alias LRow = { ambient : Vec4, diffuse : Vec4, position : Vec3 }


getRows : SLight -> LRow
getRows light =
    { ambient =
        case light.ambient.rgba of
            r::g::b::a::_ -> vec4 r g b a
            _ -> vec4 0 0 0 0
    , diffuse =
        case light.diffuse.rgba of
            r::g::b::a::_ -> vec4 r g b a
            _ -> vec4 0 0 0 0
    , position =
        case light.position of
            x::y::z::_ -> vec3 x y z
            _ -> vec3 0 0 0
    }


adaptLights : (Int, Int) -> List SLight -> { ambient : Mat4, diffuse : Mat4, position : Mat4 }
adaptLights size srcLights =
    let
        emptyVec4 = vec4 0 0 0 0
        emptyVec3 = vec3 0 0 0
        emptyRows =
            { ambient = emptyVec4
            , diffuse = emptyVec4
            , position = emptyVec3
            }
        lightRows = srcLights |> List.map getRows
    in
        case lightRows of
            [a] ->
                let
                    rowA = ( a.ambient, emptyVec4, emptyVec4, emptyVec4 )
                    rowB = ( a.diffuse, emptyVec4, emptyVec4, emptyVec4 )
                    rowC = ( a.position, emptyVec3, emptyVec3, emptyVec3 )
                in
                    lightsToMatrices size rowA rowB rowC
            [a,b] ->
                let
                    rowA = ( a.ambient, b.ambient, emptyVec4, emptyVec4 )
                    rowB = ( a.diffuse, b.diffuse, emptyVec4, emptyVec4 )
                    rowC = ( a.position, b.position, emptyVec3, emptyVec3 )
                in
                    lightsToMatrices size rowA rowB rowC
            [a,b,c] ->
                let
                    rowA = ( a.ambient, b.ambient, c.ambient, emptyVec4 )
                    rowB = ( a.diffuse, b.diffuse, c.diffuse, emptyVec4 )
                    rowC = ( a.position, b.position, c.position, emptyVec3 )
                in
                    lightsToMatrices size rowA rowB rowC
            a::b::c::d::_ ->
                let
                    rowA = ( a.ambient, b.ambient, c.ambient, d.ambient )
                    rowB = ( a.diffuse, b.diffuse, c.diffuse, d.diffuse )
                    rowC = ( a.position, b.position, c.position, d.position )
                in
                    lightsToMatrices size rowA rowB rowC
            _ ->
                { ambient = Mat4.identity
                , diffuse = Mat4.identity
                , position = Mat4.identity
                }

lightsToMatrices
    : (Int, Int)
    -> ( Vec4, Vec4, Vec4, Vec4 )
    -> ( Vec4, Vec4, Vec4, Vec4 )
    ->  ( Vec3, Vec3, Vec3, Vec3 )
    ->
    { ambient : Mat4
    , diffuse : Mat4
    , position : Mat4
    }
lightsToMatrices (w, h) ( aa, ba, ca, da ) ( ad, bd, cd, dd ) ( ap, bp, cp, dp ) =
    { ambient = Mat4.fromRecord
        { m11 = Vec4.getX aa, m12 = Vec4.getY aa, m13 = Vec4.getZ aa, m14 = Vec4.getW aa
        , m21 = Vec4.getX ba, m22 = Vec4.getY ba, m23 = Vec4.getZ ba, m24 = Vec4.getW ba
        , m31 = Vec4.getX ca, m32 = Vec4.getY ca, m33 = Vec4.getZ ca, m34 = Vec4.getW ca
        , m41 = Vec4.getX da, m42 = Vec4.getY da, m43 = Vec4.getZ da, m44 = Vec4.getW da
        } |> Mat4.transpose
    , diffuse = Mat4.fromRecord
        { m11 = Vec4.getX ad, m12 = Vec4.getY ad, m13 = Vec4.getZ ad, m14 = Vec4.getW ad
        , m21 = Vec4.getX bd, m22 = Vec4.getY bd, m23 = Vec4.getZ bd, m24 = Vec4.getW bd
        , m31 = Vec4.getX cd, m32 = Vec4.getY cd, m33 = Vec4.getZ cd, m34 = Vec4.getW cd
        , m41 = Vec4.getX dd, m42 = Vec4.getY dd, m43 = Vec4.getZ dd, m44 = Vec4.getW dd
        } |> Mat4.transpose
    , position = Mat4.fromRecord
        { m11 = Vec3.getX ap, m12 = Vec3.getY ap, m13 = Vec3.getZ ap, m14 = 0
        , m21 = Vec3.getX bp, m22 = Vec3.getY bp, m23 = Vec3.getZ bp, m24 = 0
        , m31 = Vec3.getX cp, m32 = Vec3.getY cp, m33 = Vec3.getZ cp, m34 = 0
        , m41 = Vec3.getX dp, m42 = Vec3.getY dp, m43 = Vec3.getZ dp, m44 = 0
        } |> Mat4.transpose
    }



vertexShader : WebGL.Shader Vertex Uniforms { vColor : Vec4, vPosition : Vec3 }
vertexShader =
    [glsl|

        // Precision
        precision mediump float;

        // Attributes
        attribute float aSide;
        attribute vec3 aPosition;
        attribute vec3 aCentroid;
        attribute vec3 aNormal;
        attribute vec4 aAmbient;
        attribute vec4 aDiffuse;
        attribute vec4 aColor;
        attribute vec3 aVelocity;

        attribute float aPhi;
        

        // Uniforms
        uniform mat4 cameraTranslate;
        uniform mat4 cameraRotate;
        uniform mat4 perspective;
        uniform mat4 camera;
        uniform mat4 rotation;

        uniform vec3 uResolution;

        uniform vec3 uSegment;
        uniform float uNow;

        uniform mat4 uLightPosition;
        uniform mat4 uLightAmbient;
        uniform mat4 uLightDiffuse;

        // Varyings
        varying vec4 vColor;
        varying vec3 vPosition;


        float rand(vec2 n) { 
            return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
        }

        float noise(vec2 p){
            vec2 ip = floor(p);
            vec2 u = fract(p);
            u = u*u*(3.0-2.0*u);
            
            float res = mix(
                mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
                mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
            return res*res;
        }

        float introTransition(float curTime, float len) {
          if (curTime < len) {
             return curTime / len;
          } else {
             return 1.0;
          }
        }

        vec3 trigFunc(vec3 arg) {
            return vec3(sin(arg[0]), cos(arg[1]), sin(arg[2]));
        }

        // Main
        void main() {

           // Create color
            vColor = vec4(0.0);
           // vColor = aColor;
           // vColor = vec4(aGradient, 1.0);



            // Calculate the vertex position

            float speed = 0.001;
            vec3 ranges = vec3(0.35, 0.2, 0.2);
            vec2 orbitFactor = vec2(1.0, 1.0);
            vec2 lightsSpeed = vec2(4000.0, 4000.0);
            vec2 brightnessD = vec2(3.5, 3.5);
            vec2 brightnessA = vec2(1.0, 1.0);
            vec3 position = aPosition;
            position = position + introTransition(uNow, 5000.0) * ranges * uSegment * trigFunc(aPhi + aVelocity * uNow * speed);
            position = position / uResolution * 2.0;




            // Iterate through lights
            for (int i = 0; i < 2; i++) {
                vec3 lightPosition = orbitFactor[i] * vec3(uLightPosition[i]) * trigFunc(vec3(vec2(uNow / lightsSpeed[i]), 90.0));
                vec4 lightAmbient = brightnessA[i] * uLightAmbient[i];
                vec4 lightDiffuse = brightnessD[i] * uLightDiffuse[i];

                vec3 ray = normalize(lightPosition - aCentroid);
                float illuminance = dot(aNormal, ray) ;
                illuminance = max(illuminance, 0.0);

                // Calculate ambient light
                vColor += aAmbient * lightAmbient;

                // Calculate diffuse light
                vColor += aDiffuse  * lightDiffuse * illuminance;


            }

           // Multiplied by gradients
             vColor = vColor * aColor;
          //vColor = vec4(1.0);


            // Set gl_Position
           gl_Position = cameraRotate * cameraTranslate * vec4(position, 1.0);
            //  vPosition = position;
            //   gl_Position =  camera * cameraRotate *  rotation * vec4(position, 1.0);



        }

    |]




fragmentShader : WebGL.Shader {} Uniforms { vColor : Vec4, vPosition : Vec3 }
fragmentShader =
    [glsl|

        // Precision
        precision mediump float;

        // Varyings
        varying vec4 vColor;
        varying vec3 vPosition;

        uniform vec3 uResolution;
  //      uniform float uNow;

        // Main
        void main() {

    // Set gl_FragColor
    gl_FragColor = vColor;

    vec2 st=  gl_FragCoord.xy / uResolution.xy;

    vec4 bgColor = vec4(0.0862745098, 0.0862745098, 0.0862745098, 1.0);

    gl_FragColor = mix(vColor, bgColor, pow(smoothstep(0.0, 0.37, distance(st, vec2(0.55, 0.35))), 2.0));






        }

    |]
