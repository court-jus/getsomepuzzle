'use strict';
const MANIFEST = 'flutter-app-manifest';
const TEMP = 'flutter-temp-cache';
const CACHE_NAME = 'flutter-app-cache';

const RESOURCES = {".dart_tool/dartpad/web_plugin_registrant.dart": "7ed35bc85b7658d113371ffc24d07117",
".dart_tool/package_config.json": "bb3c1b5bc9197c50637b0b67ec5d3e25",
".dart_tool/package_graph.json": "24976a00e74d8ec711d8740b9c633540",
".dart_tool/version": "b75afce8fdddf295e000a38d01bba48c",
".git/config": "07f0b02d897a427e330b7657d2342664",
".git/description": "a0a7c3fff21f2aea3cfa1d0316dd816c",
".git/FETCH_HEAD": "64b1800c5a47e61d13ec2e621946a4b0",
".git/HEAD": "5ab7a4355e4c959b0c5c008f202f51ec",
".git/hooks/applypatch-msg.sample": "ce562e08d8098926a3862fc6e7905199",
".git/hooks/commit-msg.sample": "579a3c1e12a1e74a98169175fb913012",
".git/hooks/fsmonitor-watchman.sample": "a0b2633a2c8e97501610bd3f73da66fc",
".git/hooks/post-update.sample": "2b7ea5cee3c49ff53d41e00785eb974c",
".git/hooks/pre-applypatch.sample": "054f9ffb8bfe04a599751cc757226dda",
".git/hooks/pre-commit.sample": "5029bfab85b1c39281aa9697379ea444",
".git/hooks/pre-merge-commit.sample": "39cb268e2a85d436b9eb6f47614c3cbc",
".git/hooks/pre-push.sample": "2c642152299a94e05ea26eae11993b13",
".git/hooks/pre-rebase.sample": "56e45f2bcbc8226d2b4200f7c46371bf",
".git/hooks/pre-receive.sample": "2ad18ec82c20af7b5926ed9cea6aeedd",
".git/hooks/prepare-commit-msg.sample": "2b5c047bdb474555e1787db32b2d2fc5",
".git/hooks/push-to-checkout.sample": "c7ab00c7784efeadad3ae9b228d4b4db",
".git/hooks/sendemail-validate.sample": "4d67df3a8d5c98cb8565c07e42be0b04",
".git/hooks/update.sample": "647ae13c682f7827c22f5fc08a03674e",
".git/index": "5da7da95914f216c36b7d34461e22590",
".git/info/exclude": "036208b4a1ab4a235d75c181e685e5a3",
".git/logs/HEAD": "fb73f0c1ee85eb3b65731aa75b3143bc",
".git/logs/refs/heads/gh-pages": "fb73f0c1ee85eb3b65731aa75b3143bc",
".git/objects/pack/pack-1dfb277fa84a2b109f5ff254f9cb2cacd70a8111.idx": "2c07b917caf369d0302a25327541a8e4",
".git/objects/pack/pack-1dfb277fa84a2b109f5ff254f9cb2cacd70a8111.pack": "974e7b951f1b5b7c659e41ef4010cb60",
".git/objects/pack/pack-1dfb277fa84a2b109f5ff254f9cb2cacd70a8111.rev": "897afda535904d990fed2807dfc18123",
".git/objects/pack/pack-ae6178f769a6c5c7b52a60f8a551fd043b3ca1af.idx": "8b7abe7d7206eeb16ca960563d9f5e5b",
".git/objects/pack/pack-ae6178f769a6c5c7b52a60f8a551fd043b3ca1af.pack": "b5b77b1240322356c3111e74c7051795",
".git/objects/pack/pack-ae6178f769a6c5c7b52a60f8a551fd043b3ca1af.rev": "ecfb15504309767d62bd8d5d86be5d7d",
".git/packed-refs": "3b8d15b8641152781f228932eeba565b",
".git/refs/heads/gh-pages": "f15fb3b52988fe5cc9332448906fc007",
".github/workflows/ci.yml": "b76374a27674b40b4ec427b3fac2bccf",
".idea/libraries/Dart_SDK.xml": "b7ba9da797f7ba4bcffa02d8562d8eea",
".idea/libraries/KotlinJavaRuntime.xml": "de38cfadca3106f8aff5ab15dd81692f",
".idea/modules.xml": "3867275a5e85f3eb0ad5db7870554b38",
".idea/runConfigurations/main_dart.xml": "0ecf958af289efc3fc1927aa27a8442f",
".idea/workspace.xml": "25155dfb2368a7e35e1ebbecd505a418",
"android/web_android.iml": "273d851cbe25579b8e6ee48886fa4d6a",
"assets/AssetManifest.bin": "6b8ffecae6379b2a9f413e99d9dbeea7",
"assets/AssetManifest.bin.json": "170f737b6e78ad3b15e8ea33d5534ed3",
"assets/AssetManifest.json": "d65612a80f05c6b6726bcf495868cd3c",
"assets/assets/help.en.md": "9424e48f8504b41f2d2590d74833c731",
"assets/assets/help.fr.md": "01b03f313b1b203536e7f544ae35735c",
"assets/assets/puzzles.txt": "471b810df51c868bcc598f0bd83c0d45",
"assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"assets/fonts/MaterialIcons-Regular.otf": "edbbae8ab650bf025961455c966f4cb3",
"assets/NOTICES": "a2ff4aa8d72c8e752e4fa6447e5a4980",
"assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
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
"flutter_bootstrap.js": "ee343a1b505477adfd05bd719608ac3e",
"getsomepuzzle/.dart_tool/dartpad/web_plugin_registrant.dart": "7ed35bc85b7658d113371ffc24d07117",
"getsomepuzzle/.dart_tool/package_config.json": "bb3c1b5bc9197c50637b0b67ec5d3e25",
"getsomepuzzle/.dart_tool/package_graph.json": "24976a00e74d8ec711d8740b9c633540",
"getsomepuzzle/.dart_tool/version": "b75afce8fdddf295e000a38d01bba48c",
"getsomepuzzle/.github/workflows/ci.yml": "b76374a27674b40b4ec427b3fac2bccf",
"getsomepuzzle/.idea/libraries/Dart_SDK.xml": "b7ba9da797f7ba4bcffa02d8562d8eea",
"getsomepuzzle/.idea/libraries/KotlinJavaRuntime.xml": "de38cfadca3106f8aff5ab15dd81692f",
"getsomepuzzle/.idea/modules.xml": "3867275a5e85f3eb0ad5db7870554b38",
"getsomepuzzle/.idea/runConfigurations/main_dart.xml": "0ecf958af289efc3fc1927aa27a8442f",
"getsomepuzzle/.idea/workspace.xml": "25155dfb2368a7e35e1ebbecd505a418",
"getsomepuzzle/android/web_android.iml": "273d851cbe25579b8e6ee48886fa4d6a",
"getsomepuzzle/assets/AssetManifest.bin": "6b8ffecae6379b2a9f413e99d9dbeea7",
"getsomepuzzle/assets/AssetManifest.bin.json": "170f737b6e78ad3b15e8ea33d5534ed3",
"getsomepuzzle/assets/AssetManifest.json": "d65612a80f05c6b6726bcf495868cd3c",
"getsomepuzzle/assets/assets/help.en.md": "9424e48f8504b41f2d2590d74833c731",
"getsomepuzzle/assets/assets/help.fr.md": "01b03f313b1b203536e7f544ae35735c",
"getsomepuzzle/assets/assets/puzzles.txt": "471b810df51c868bcc598f0bd83c0d45",
"getsomepuzzle/assets/FontManifest.json": "dc3d03800ccca4601324923c0b1d6d57",
"getsomepuzzle/assets/fonts/MaterialIcons-Regular.otf": "edbbae8ab650bf025961455c966f4cb3",
"getsomepuzzle/assets/NOTICES": "a2ff4aa8d72c8e752e4fa6447e5a4980",
"getsomepuzzle/assets/packages/cupertino_icons/assets/CupertinoIcons.ttf": "33b7d9392238c04c131b6ce224e13711",
"getsomepuzzle/assets/shaders/ink_sparkle.frag": "ecc85a2e95f5e9f53123dcaf8cb9b6ce",
"getsomepuzzle/canvaskit/canvaskit.js": "140ccb7d34d0a55065fbd422b843add6",
"getsomepuzzle/canvaskit/canvaskit.js.symbols": "58832fbed59e00d2190aa295c4d70360",
"getsomepuzzle/canvaskit/canvaskit.wasm": "07b9f5853202304d3b0749d9306573cc",
"getsomepuzzle/canvaskit/chromium/canvaskit.js": "5e27aae346eee469027c80af0751d53d",
"getsomepuzzle/canvaskit/chromium/canvaskit.js.symbols": "193deaca1a1424049326d4a91ad1d88d",
"getsomepuzzle/canvaskit/chromium/canvaskit.wasm": "24c77e750a7fa6d474198905249ff506",
"getsomepuzzle/canvaskit/skwasm.js": "1ef3ea3a0fec4569e5d531da25f34095",
"getsomepuzzle/canvaskit/skwasm.js.symbols": "0088242d10d7e7d6d2649d1fe1bda7c1",
"getsomepuzzle/canvaskit/skwasm.wasm": "264db41426307cfc7fa44b95a7772109",
"getsomepuzzle/canvaskit/skwasm_heavy.js": "413f5b2b2d9345f37de148e2544f584f",
"getsomepuzzle/canvaskit/skwasm_heavy.js.symbols": "3c01ec03b5de6d62c34e17014d1decd3",
"getsomepuzzle/canvaskit/skwasm_heavy.wasm": "8034ad26ba2485dab2fd49bdd786837b",
"getsomepuzzle/favicon.png": "5dcef449791fa27946b3d35ad8803796",
"getsomepuzzle/flutter.js": "888483df48293866f9f41d3d9274a779",
"getsomepuzzle/flutter_bootstrap.js": "bd87e8e513e228101dd2a5d5d7f7ce17",
"getsomepuzzle/icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"getsomepuzzle/icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"getsomepuzzle/icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"getsomepuzzle/icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"getsomepuzzle/index.html": "12235363989c288d3d9b771a7cd2323d",
"getsomepuzzle/main.dart.js": "4c7156126a8a7865cd43f0640f9621ae",
"getsomepuzzle/manifest.json": "f31894fbe418c793024c5699575b8284",
"getsomepuzzle/version.json": "8133178c1c656458ae08d6d5d25483ad",
"getsomepuzzle/web.iml": "f9bf5c490675c84d098e6772a6f2a796",
"icons/Icon-192.png": "ac9a721a12bbc803b44f645561ecb1e1",
"icons/Icon-512.png": "96e752610906ba2a93c65f8abe1645f1",
"icons/Icon-maskable-192.png": "c457ef57daa1d16f64b27b786ec2ea3c",
"icons/Icon-maskable-512.png": "301a7604d45b3e739efc881eb04896ea",
"index.html": "12235363989c288d3d9b771a7cd2323d",
"/": "12235363989c288d3d9b771a7cd2323d",
"main.dart.js": "f18fa6a70beb0b4acfa84c1984ac278f",
"manifest.json": "f31894fbe418c793024c5699575b8284",
"version.json": "8133178c1c656458ae08d6d5d25483ad",
"web.iml": "f9bf5c490675c84d098e6772a6f2a796"};
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
