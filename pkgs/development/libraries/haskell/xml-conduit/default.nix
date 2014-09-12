# This file was auto-generated by cabal2nix. Please do NOT edit manually!

{ cabal, attoparsec, attoparsecConduit, blazeBuilder
, blazeBuilderConduit, blazeHtml, blazeMarkup, conduit
, conduitExtra, dataDefault, deepseq, hspec, HUnit, monadControl
, resourcet, systemFilepath, text, transformers, xmlTypes
}:

cabal.mkDerivation (self: {
  pname = "xml-conduit";
  version = "1.2.1";
  sha256 = "1bh0d2fqcdbx2dq5ybipf7ws59blrb8yd98z1rnbvv1fj9r0xw10";
  buildDepends = [
    attoparsec attoparsecConduit blazeBuilder blazeBuilderConduit
    blazeHtml blazeMarkup conduit conduitExtra dataDefault deepseq
    monadControl resourcet systemFilepath text transformers xmlTypes
  ];
  testDepends = [
    blazeMarkup conduit hspec HUnit resourcet text transformers
    xmlTypes
  ];
  jailbreak = true;
  meta = {
    homepage = "http://github.com/snoyberg/xml";
    description = "Pure-Haskell utilities for dealing with XML with the conduit package";
    license = self.stdenv.lib.licenses.bsd3;
    platforms = self.ghc.meta.platforms;
  };
})
