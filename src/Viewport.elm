module Viewport exposing
    ( State
    , Viewport
    , find
    )


import Math.Matrix4 as Mat4 exposing (Mat4)
import Math.Vector3 as Vec3 exposing (vec3)


type alias State =
    { theta : Float
    }


type alias Viewport a =
    { a
    | rotation : Mat4
    , perspective : Mat4
    , camera : Mat4
    -- , shade : Float
    , cameraTranslate : Mat4
    , cameraRotate : Mat4
    }


find : State -> Viewport {}
find { theta } =
    { rotation
        = Mat4.makeRotate (3 * theta) (vec3 0 1 0)
    , perspective
        = Mat4.makePerspective 95 1.5 0.1 3000
    , camera = Mat4.makeLookAt (vec3 1 0.5 -0.8) (vec3 -0.5 0.1 0) (vec3 0 1 0)
    --, shade = 0.8
    , cameraTranslate = Mat4.makeTranslate (vec3 (1/3) (1/80) (-1/16))
    , cameraRotate = Mat4.makeRotate (2) (vec3 1 0 0)
    }


-- { perspective = perspective (t / 1000) }
-- perspective : Float -> Mat4
-- perspective t =
--     Mat4.mul
--         (Mat4.makePerspective 45 1 0.01 100)
--         (Mat4.makeLookAt (vec3 (4 * cos t) 0 (4 * sin t)) (vec3 0 0 0) (vec3 0 1 0))