// Lets the demo import the SDK straight from source (../../react-native/src) without a
// build step: watch that folder so Metro transpiles its TS, map the package name to it,
// and resolve react/react-native from the demo's own node_modules.
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const projectRoot = __dirname;
const sdkRoot = path.resolve(projectRoot, '../../react-native');

const config = getDefaultConfig(projectRoot);
config.watchFolders = [sdkRoot];
config.resolver.nodeModulesPaths = [path.resolve(projectRoot, 'node_modules')];
config.resolver.extraNodeModules = {
  '@goldenkrill/react-native': sdkRoot,
};

module.exports = config;
