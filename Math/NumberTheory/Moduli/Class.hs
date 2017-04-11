-- |
-- Module:      Math.NumberTheory.Moduli.Class
-- Copyright:   (c) 2017 Andrew Lelechenko
-- Licence:     MIT
-- Maintainer:  Andrew Lelechenko <andrew.lelechenko@gmail.com>
-- Stability:   Provisional
-- Portability: Non-portable (GHC extensions)
--
-- Safe modular arithmetic with modulo on type level.
--

{-# LANGUAGE CPP                 #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE GADTs               #-}
{-# LANGUAGE KindSignatures      #-}
{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE RankNTypes          #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving  #-}

module Math.NumberTheory.Moduli.Class
  ( Mod(..)
  , getMod
  , invertMod
  , powMod
  , (^/)

  , SomeMod(..)
  , modulo
  , invertSomeMod
  , powSomeMod

  , Nat
  , KnownNat
  ) where

import Data.Proxy
import Data.Ratio
import Data.Type.Equality
#if __GLASGOW_HASKELL__ < 709
import Data.Word
#endif
import GHC.Integer.GMP.Internals
import GHC.TypeLits
import Numeric.Natural

-- | Wrapper for residues modulo @m@.
newtype Mod (m :: Nat) = Mod
  { getVal :: Integer -- ^ Extract residue.
  } deriving (Eq, Ord)

instance KnownNat m => Show (Mod m) where
  show m = "(" ++ show (getVal m) ++ " `modulo` " ++ show (natVal m) ++ ")"

instance KnownNat m => Num (Mod m) where
  mx@(Mod x) + Mod y =
    Mod $ if xy >= m then xy - m else xy
    where
      xy = x + y
      m = natVal mx
  {-# INLINE (+) #-}
  mx@(Mod x) - Mod y =
    Mod $ if x >= y then x - y else m + x - y
    where
      m = natVal mx
  {-# INLINE (-) #-}
  negate mx@(Mod x) =
    Mod $ if x == 0 then 0 else natVal mx - x
  {-# INLINE negate #-}
  mx@(Mod x) * Mod y =
    Mod $ x * y `mod` natVal mx
  {-# INLINE (*) #-}
  abs = id
  {-# INLINE abs #-}
  signum = const $ Mod 1
  {-# INLINE signum #-}
  fromInteger x = mx
    where
      mx = Mod $ fromInteger $ x `mod` natVal mx
  {-# INLINE fromInteger #-}

instance KnownNat m => Fractional (Mod m) where
  fromRational r = case denominator r of
    1   -> num
    den -> num / fromInteger den
    where
      num = fromInteger (numerator r)
  {-# INLINE fromRational #-}
  recip mx = case invertMod mx of
    Nothing -> error $ "recip{Mod}: residue is not coprime with modulo"
    Just y  -> y
  {-# INLINE recip #-}

-- | Linking type and value level: extract modulo @m@ as a value.
getMod :: KnownNat m => Mod m -> Natural
getMod = fromInteger . natVal
{-# INLINE getMod #-}

invertMod :: KnownNat m => Mod m -> Maybe (Mod m)
invertMod mx@(Mod x) = case recipModInteger x (natVal mx) of
  0 -> Nothing
  y -> Just (Mod y)
{-# INLINABLE invertMod #-}

powMod :: (KnownNat m, Integral a) => Mod m -> a -> Mod m
powMod mx@(Mod x) a
  | a < 0     = error $ "^{Mod}: negative exponent"
  | otherwise = Mod $ powModInteger x (toInteger a) (natVal mx)
{-# INLINABLE [1] powMod #-}

{-# SPECIALISE [1] powMod ::
  KnownNat m => Mod m -> Integer -> Mod m,
  KnownNat m => Mod m -> Natural -> Mod m,
  KnownNat m => Mod m -> Int     -> Mod m,
  KnownNat m => Mod m -> Word    -> Mod m #-}

{-# RULES
"powMod/2/Integer"     forall x. powMod x (2 :: Integer) = let u = x in u*u
"powMod/3/Integer"     forall x. powMod x (3 :: Integer) = let u = x in u*u*u
"powMod/2/Int"         forall x. powMod x (2 :: Int)     = let u = x in u*u
"powMod/3/Int"         forall x. powMod x (3 :: Int)     = let u = x in u*u*u #-}

(^/) :: (KnownNat m, Integral a) => Mod m -> a -> Mod m
(^/) = powMod
{-# INLINE (^/) #-}

infixr 8 ^/

-- Unfortunately, such rule never fires due to technical details
-- of type class implementation is Core.
-- {-# RULES "^/Mod" forall (x :: KnownNat m => Mod m) p. x ^ p = x ^/ p #-}

data SomeMod where
  SomeMod :: KnownNat m => Mod m -> SomeMod
  InfMod  :: Rational -> SomeMod

instance Eq SomeMod where
  SomeMod mx == SomeMod my = getMod mx == getMod my && getVal mx == getVal my
  InfMod rx  == InfMod ry  = rx == ry
  _          == _          = False

instance Show SomeMod where
  show = \case
    SomeMod m -> show m
    InfMod  r -> show r

modulo :: Integer -> Natural -> SomeMod
modulo n m = case someNatVal m' of
  Nothing                       -> error "modulo: negative modulo"
  Just (SomeNat (_ :: Proxy t)) -> SomeMod (Mod r :: Mod t)
  where
    m' = fromIntegral m
    r = fromInteger $ n `mod` m'
{-# INLINABLE modulo #-}

liftUnOp
  :: (forall k. KnownNat k => Mod k -> Mod k)
  -> (Rational -> Rational)
  -> SomeMod
  -> SomeMod
liftUnOp fm fr = \case
  SomeMod m -> SomeMod (fm m)
  InfMod  r -> InfMod  (fr r)
{-# INLINEABLE liftUnOp #-}

liftBinOpMod
  :: (KnownNat m, KnownNat n)
  => (forall k. KnownNat k => Mod k -> Mod k -> Mod k)
  -> Mod m
  -> Mod n
  -> SomeMod
liftBinOpMod f mx@(Mod x) my@(Mod y) = case someNatVal m of
  Nothing                       -> error "modulo: negative modulo"
  Just (SomeNat (_ :: Proxy t)) -> SomeMod (Mod (x `mod` m) `f` Mod (y `mod` m) :: Mod t)
  where
    m = natVal mx `gcd` natVal my

liftBinOp
  :: (forall k. KnownNat k => Mod k -> Mod k -> Mod k)
  -> (Rational -> Rational -> Rational)
  -> SomeMod
  -> SomeMod
  -> SomeMod
liftBinOp _ fr (InfMod rx)  (InfMod ry)  = InfMod  (rx `fr` ry)
liftBinOp fm _ (InfMod rx)  (SomeMod my) = SomeMod (fromRational rx `fm` my)
liftBinOp fm _ (SomeMod mx) (InfMod ry)  = SomeMod (mx `fm` fromRational ry)
liftBinOp fm _ (SomeMod (mx :: Mod m)) (SomeMod (my :: Mod n))
  = case (Proxy :: Proxy m) `sameNat` (Proxy :: Proxy n) of
    Nothing   -> liftBinOpMod fm mx my
    Just Refl -> SomeMod (mx `fm` my)

-- | 'fromInteger' implementation does not make much sense,
-- it is present for the sake of completeness.
instance Num SomeMod where
  (+)    = liftBinOp (+) (+)
  (-)    = liftBinOp (-) (+)
  negate = liftUnOp negate negate
  {-# INLINE negate #-}
  (*)    = liftBinOp (*) (*)
  abs    = id
  {-# INLINE abs #-}
  signum = const 1
  {-# INLINE signum #-}
  fromInteger = InfMod . fromInteger
  {-# INLINE fromInteger #-}

-- | 'fromRational' implementation does not make much sense,
-- it is present for the sake of completeness.
instance Fractional SomeMod where
  fromRational = InfMod
  {-# INLINE fromRational #-}
  recip x = case invertSomeMod x of
    Nothing -> error $ "recip{SomeMod}: residue is not coprime with modulo"
    Just y  -> y

invertSomeMod :: SomeMod -> Maybe SomeMod
invertSomeMod = \case
  SomeMod m -> fmap SomeMod (invertMod m)
  InfMod  r -> Just (InfMod (recip r))
{-# INLINABLE [1] invertSomeMod #-}

{-# SPECIALISE [1] powSomeMod ::
  SomeMod -> Integer -> SomeMod,
  SomeMod -> Natural -> SomeMod,
  SomeMod -> Int     -> SomeMod,
  SomeMod -> Word    -> SomeMod #-}

powSomeMod :: Integral a => SomeMod -> a -> SomeMod
powSomeMod (SomeMod m) a = SomeMod (m ^/ a)
powSomeMod (InfMod  r) a = InfMod  (r ^  a)
{-# INLINABLE [1] powSomeMod #-}

{-# RULES "^/SomeMod" forall x p. x ^ p = powSomeMod x p #-}
