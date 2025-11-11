'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {".dart_tool/dartpad/web_plugin_registrant.dart": "7ed35bc85b7658d113371ffc24d07117",
".dart_tool/package_config.json": "bb3c1b5bc9197c50637b0b67ec5d3e25",
".dart_tool/package_graph.json": "24976a00e74d8ec711d8740b9c633540",
".dart_tool/version": "b75afce8fdddf295e000a38d01bba48c",
".idea/libraries/Dart_SDK.xml": "b7ba9da797f7ba4bcffa02d8562d8eea",
".idea/libraries/KotlinJavaRuntime.xml": "de38cfadca3106f8aff5ab15dd81692f",
".idea/modules.xml": "3867275a5e85f3eb0ad5db7870554b38",
".idea/runConfigurations/main_dart.xml": "0ecf958af289efc3fc1927aa27a8442f",
".idea/workspace.xml": "25155dfb2368a7e35e1ebbecd505a418",
"android/web_android.iml": "273d851cbe25579b8e6ee48886fa4d6a",
"assets/AssetManifest.bin": "eced690e3470292e3d1d909fff19836a",
"assets/AssetManifest.bin.json": "6ccfb9e44bb2c4695eca9ff0d0a1e1e5",
"assets/AssetManifest.json": "7acd4a4fe258c7d763c28693371e87e4",
"assets/assets/help.en.md": "3188dddf766cac136e8ead0ec4f512d3",
"assets/assets/help.es.md": "de3544ff2115af4f8488e1eed3d79b27",
"assets/assets/help.fr.md": "d685d2764854fab61ac8f019fa40952c",
"assets/assets/high_ratio.txt": "9a6ed0d199fb93a73e7781b2715695b2",
"assets/assets/new_puzzles.txt": "a7cb619e604a49a4cc3efa15486587d6",
"assets/assets/puzzles.txt": "e5431ff56e7c7520cc6d2c5186bfc899",
"assets/assets/tutorial.txt": "85d570ff24da998127d3d7f96752c3c3",
"assets/assets/TX/en/text1.md": "1a7577bae74d8522c97fc5784af4c04f",
"assets/assets/TX/en/text10.md": "2d32ab8bceb35adaf34b854fdea2e2fb",
"assets/assets/TX/en/text11.md": "5bc2a635e2e7ea69672818d4a91024f7",
"assets/assets/TX/en/text12.md": "6e1e4a013395361c520163d2690561a3",
"assets/assets/TX/en/text13.md": "efe3a21d29e8d21a2b8c66ed1dc6344f",
"assets/assets/TX/en/text14.md": "0433e608a28f2583f3dc7c270b542963",
"assets/assets/TX/en/text15.md": "240e1c5f905fd04b7676ad82e7367232",
"assets/assets/TX/en/text16.md": "c9af728d73a05d0f53926797822708b0",
"assets/assets/TX/en/text17.md": "fc3f2ecded986b43cf8650bdfb9d1a58",
"assets/assets/TX/en/text18.md": "825be84e0ace34e0b0890de297d45460",
"assets/assets/TX/en/text19.md": "f6a69b37200de408225c848972badd68",
"assets/assets/TX/en/text2.md": "78d5c6133ebbf3f18e132a9c94e6c67b",
"assets/assets/TX/en/text20.md": "21d874e0a58d6fdbf9759e81280c1519",
"assets/assets/TX/en/text21.md": "a0414691445bc85f9c2ac128ac880336",
"assets/assets/TX/en/text22.md": "1c6156f493d173fa7c8cf5164cc68fb1",
"assets/assets/TX/en/text23.md": "a75934fbee01ae5c7cf39bea1b1fe868",
"assets/assets/TX/en/text3.md": "470ef68fbc9048494580801736093324",
"assets/assets/TX/en/text4.md": "5a4fe9854cf3e0bd9a42509441c59be6",
"assets/assets/TX/en/text5.md": "836783be51b752d76d86be32788c9aee",
"assets/assets/TX/en/text6.md": "ce091a1b6cfd8429b5ad7b5dc8a2c4ac",
"assets/assets/TX/en/text7.md": "4c98199f474564ac73a6d361d59431c1",
"assets/assets/TX/en/text8.md": "4542459fc92434feecb0bd31c060b333",
"assets/assets/TX/en/text9.md": "44f2a00c5c85c9d06fb9d25037c7e706",
"assets/assets/TX/es/text1.md": "1a7577bae74d8522c97fc5784af4c04f",
"assets/assets/TX/es/text10.md": "2d32ab8bceb35adaf34b854fdea2e2fb",
"assets/assets/TX/es/text11.md": "5bc2a635e2e7ea69672818d4a91024f7",
"assets/assets/TX/es/text12.md": "6e1e4a013395361c520163d2690561a3",
"assets/assets/TX/es/text13.md": "efe3a21d29e8d21a2b8c66ed1dc6344f",
"assets/assets/TX/es/text14.md": "0433e608a28f2583f3dc7c270b542963",
"assets/assets/TX/es/text15.md": "240e1c5f905fd04b7676ad82e7367232",
"assets/assets/TX/es/text16.md": "c9af728d73a05d0f53926797822708b0",
"assets/assets/TX/es/text17.md": "fc3f2ecded986b43cf8650bdfb9d1a58",
"assets/assets/TX/es/text18.md": "825be84e0ace34e0b0890de297d45460",
"assets/assets/TX/es/text19.md": "f6a69b37200de408225c848972badd68",
"assets/assets/TX/es/text2.md": "78d5c6133ebbf3f18e132a9c94e6c67b",
"assets/assets/TX/es/text20.md": "21d874e0a58d6fdbf9759e81280c1519",
"assets/assets/TX/es/text21.md": "a0414691445bc85f9c2ac128ac880336",
"assets/assets/TX/es/text22.md": "1c6156f493d173fa7c8cf5164cc68fb1",
"assets/assets/TX/es/text23.md": "a75934fbee01ae5c7cf39bea1b1fe868",
"assets/assets/TX/es/text3.md": "470ef68fbc9048494580801736093324",
"assets/assets/TX/es/text4.md": "5a4fe9854cf3e0bd9a42509441c59be6",
"assets/assets/TX/es/text5.md": "836783be51b752d76d86be32788c9aee",
"assets/assets/TX/es/text6.md": "ce091a1b6cfd8429b5ad7b5dc8a2c4ac",
"assets/assets/TX/es/text7.md": "4c98199f474564ac73a6d361d59431c1",
"assets/assets/TX/es/text8.md": "4542459fc92434feecb0bd31c060b333",
"assets/assets/TX/es/text9.md": "44f2a00c5c85c9d06fb9d25037c7e706",
"assets/assets/TX/fr/text1.md": "47a26a3dadc22450565c53f9bf049558",
"assets/assets/TX/fr/text10.md": "e24097ae9d3c0bd733439dd1b58d75cb",
"assets/assets/TX/fr/text11.md": "cd08438ebac4899fd426838032895488",
"assets/assets/TX/fr/text12.md": "b6068d91c4ef7526d97cde8b797435b8",
"assets/assets/TX/fr/text13.md": "e61c54766b8aa10e1c02305d31c0e48b",
"assets/assets/TX/fr/text14.md": "3d8fbf26cd184b6a7b71b2c312126d4d",
"assets/assets/TX/fr/text15.md": "27fb87a6fcec85f855b34345a192aa21",
"assets/assets/TX/fr/text16.md": "5fca863ea4bfed16292ea93ef8d49741",
"assets/assets/TX/fr/text17.md": "0d154d09a7a066d0b0cf86cc982afe40",
"assets/assets/TX/fr/text18.md": "69c67c904a7e8aa6f8363d96da64fb7f",
"assets/assets/TX/fr/text19.md": "808b3ed0ce99e3bffe9206a7dd977fe1",
"assets/assets/TX/fr/text2.md": "8c9b4d3ca6613807440abf3e1050252b",
"assets/assets/TX/fr/text20.md": "5732b956896f1f5b073bb0accf581da0",
"assets/assets/TX/fr/text21.md": "0fa4a9a3908f250116eb1f5f02e2cd5c",
"assets/assets/TX/fr/text22.md": "88bfe5ff94f1f7d037bb7e0b8d7c298b",
"assets/assets/TX/fr/text23.md": "cd95b4b229a8a3447855d88c658f87e5",
"assets/assets/TX/fr/text3.md": "f8e6b927fb3a3bb00f260ebd0eb8c37d",
"assets/assets/TX/fr/text4.md": "6695926d3a7597e05b085720c85bb081",
"assets/assets/TX/fr/text5.md": "1fdbacb68f4bd80d64cb97d76d31249a",
"assets/assets/TX/fr/text6.md": "208ea54ce91dc16b1beeb44002e85b79",
"assets/assets/TX/fr/text7.md": "c9a85379041ce7b0e76b7bfc30a662db",
"assets/assets/TX/fr/text8.md": "47c32230285bb09be6bb5b40c9e1f0f2",
"assets/assets/TX/fr/text9.md": "ce108ee32ce0436bcc3f8233baa76db7",
"assets/FontManifest.json": "c75f7af11fb9919e042ad2ee704db319",
"assets/fonts/MaterialIcons-Regular.otf": "185651bc7410e7083214d2427a1b9ea0",
"assets/NOTICES": "a0b28515170b587e985dfff379124a41",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"assets/packages/font_awesome_flutter/lib/fonts/Font-Awesome-7-Brands-Regular-400.otf": "1fcba7a59e49001aa1b4409a25d425b0",
"assets/packages/font_awesome_flutter/lib/fonts/Font-Awesome-7-Free-Regular-400.otf": "1d96a9e2b5f0a7594ff518ccd40692b2",
"assets/packages/font_awesome_flutter/lib/fonts/Font-Awesome-7-Free-Solid-900.otf": "8ad9b9ce32aada4f3bcc4a24f2c1a8d6",
"assets/packages/wakelock_plus/assets/no_sleep.js": "7748a45cd593f33280669b29c2c8919a",
"assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"favicon.png": "5dcef449791fa27946b3d35ad8803796",
"flutter.js": "888483df48293866f9f41d3d9274a779",
"flutter_bootstrap.js": "aa2d6696143893a1ae2e7e425dfe93dd",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "b5ec37a5612c1f4c2b0923618dbc64f7",
"/": "b5ec37a5612c1f4c2b0923618dbc64f7",
"main.dart.js": "8a3a066796a835405a10ce584d6cfc91",
"manifest.json": "7fe2430ffa2381ca50c6a5c56bd22896",
"version.json": "31b37745816a037210256b7296ffcecd"};
// The application shell files that are downloaded before a service worker can
// start.
const CORE = ["main.dart.js",
"index.html",
"flutter_bootstrap.js",
"assets/AssetManifest.bin.json",
"assets/FontManifest.json"];

// During install, the TEMP cache is populated with the application shell files.
self.addEventListener("install", (event) => {
  self.skipWaiting();
  return event.waitUntil(
    caches.open(TEMP).then((cache) => {
      return cache.addAll(
        CORE.map((value) => new Request(value, {'cache': 'reload'})));
    })
  );
});
// During activate, the cache is populated with the temp files downloaded in
// install. If this service worker is upgrading from one with a saved
// MANIFEST, then use this to retain unchanged resource files.
self.addEventListener("activate", function(event) {
  return event.waitUntil(async function() {
    try {
      var contentCache = await caches.open(CACHE_NAME);
      var tempCache = await caches.open(TEMP);
      var manifestCache = await caches.open(MANIFEST);
      var manifest = await manifestCache.match('manifest');
      // When there is no prior manifest, clear the entire cache.
      if (!manifest) {
        await caches.delete(CACHE_NAME);
        contentCache = await caches.open(CACHE_NAME);
        for (var request of await tempCache.keys()) {
          var response = await tempCache.match(request);
          await contentCache.put(request, response);
        }
        await caches.delete(TEMP);
        // Save the manifest to make future upgrades efficient.
        await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
        // Claim client to enable caching on first launch
        self.clients.claim();
        return;
      }
      var oldManifest = await manifest.json();
      var origin = self.location.origin;
      for (var request of await contentCache.keys()) {
        var key = request.url.substring(origin.length + 1);
        if (key == "") {
          key = "/";
        }
        // If a resource from the old manifest is not in the new cache, or if
        // the MD5 sum has changed, delete it. Otherwise the resource is left
        // in the cache and can be reused by the new service worker.
        if (!RESOURCES[key] || RESOURCES[key] != oldManifest[key]) {
          await contentCache.delete(request);
        }
      }
      // Populate the cache with the app shell TEMP files, potentially overwriting
      // cache files preserved above.
      for (var request of await tempCache.keys()) {
        var response = await tempCache.match(request);
        await contentCache.put(request, response);
      }
      await caches.delete(TEMP);
      // Save the manifest to make future upgrades efficient.
      await manifestCache.put('manifest', new Response(JSON.stringify(RESOURCES)));
      // Claim client to enable caching on first launch
      self.clients.claim();
      return;
    } catch (err) {
      // On an unhandled exception the state of the cache cannot be guaranteed.
      console.error('Failed to upgrade service worker: ' + err);
      await caches.delete(CACHE_NAME);
      await caches.delete(TEMP);
      await caches.delete(MANIFEST);
    }
  }());
});
// The fetch handler redirects requests for RESOURCE files to the service
// worker cache.
self.addEventListener("fetch", (event) => {
  if (event.request.method !== 'GET') {
    return;
  }
  var origin = self.location.origin;
  var key = event.request.url.substring(origin.length + 1);
  // Redirect URLs to the index.html
  if (key.indexOf('?v=') != -1) {
    key = key.split('?v=')[0];
  }
  if (event.request.url == origin || event.request.url.startsWith(origin + '/#') || key == '') {
    key = '/';
  }
  // If the URL is not the RESOURCE list then return to signal that the
  // browser should take over.
  if (!RESOURCES[key]) {
    return;
  }
  // If the URL is the index.html, perform an online-first request.
  if (key == '/') {
    return onlineFirst(event);
  }
  event.respondWith(caches.open(CACHE_NAME)
    .then((cache) =>  {
      return cache.match(event.request).then((response) => {
        // Either respond with the cached resource, or perform a fetch and
        // lazily populate the cache only if the resource was successfully fetched.
        return response || fetch(event.request).then((response) => {
          if (response && Boolean(response.ok)) {
            cache.put(event.request, response.clone());
          }
          return response;
        });
      })
    })
  );
});
self.addEventListener('message', (event) => {
  // SkipWaiting can be used to immediately activate a waiting service worker.
  // This will also require a page refresh triggered by the main worker.
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
    return;
  }
  if (event.data === 'downloadOffline') {
    downloadOffline();
    return;
  }
});
// Download offline will check the RESOURCES for all files not in the cache
// and populate them.
async function downloadOffline() {
  var resources = [];
  var contentCache = await caches.open(CACHE_NAME);
  var currentContent = {};
  for (var request of await contentCache.keys()) {
    var key = request.url.substring(origin.length + 1);
    if (key == "") {
      key = "/";
    }
    currentContent[key] = true;
  }
  for (var resourceKey of Object.keys(RESOURCES)) {
    if (!currentContent[resourceKey]) {
      resources.push(resourceKey);
    }
  }
  return contentCache.addAll(resources);
}
// Attempt to download the resource online before falling back to
// the offline cache.
function onlineFirst(event) {
  return event.respondWith(
    fetch(event.request).then((response) => {
      return caches.open(CACHE_NAME).then((cache) => {
        cache.put(event.request, response.clone());
        return response;
      });
    }).catch((error) => {
      return caches.open(CACHE_NAME).then((cache) => {
        return cache.match(event.request).then((response) => {
          if (response != null) {
            return response;
          }
          throw error;
        });
      });
    })
  );
}
