# Moon-city lobby environment

Built-in image generation, using the environment visible on the tablet in the user-supplied IMG_3864.webp as reference. No people, device frame, UI, text or characters are included in the asset.

Final asset: App/Assets.xcassets/ArenaLobbyMoonCity.imageset/moon-city.jpg. 1672 x 941 RGB, JPEG quality 93, approximately 176 KiB. Original generation PNG retained in the working workspace. The source image is an environment illustration rather than a screenshot of the running game.

Prompt: Create a production landscape game environment based only on the blue moonlit city visible on the tablet screen. Royal cobalt blue night, enormous pale pink central moon with violet halo, layered angular navy city, pink edge lights, dark rooftop landing pad with segmented neon perimeter. Keep center empty for the live 3D hero and clear margins for interactive controls. Crisp polished 3D cartoon mobile-game illustration. No people, characters, UI, writing, watermark, logos or surrounding photograph.

Integration: one static image in SwiftUI; live character, menus, state and interactions remain native. Cover fit preserves moon aspect ratio. Removed the additional SceneKit pedestal to avoid two overlapping stages. Lobby rim light uses the existing showcase clock; reduce-motion preference disables modulation. Combat scene is untouched.

Validation: source image decoded and dimensions checked locally. Simulator resource-decoding test added. iOS compilation and actual visual comparison remain required. This asset does not establish original-game fidelity; the existing character models differ from the reference.
