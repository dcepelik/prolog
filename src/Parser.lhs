> module Parser (Term (Atom, Number, Variable, Compound), Rule (Rule), Program, parse, term, program) where

> import Data.Char
> import Data.List
> import Control.Monad
> import Control.Applicative

data structures

> data Term = Atom String
>           | Number Int
>           | Variable String
>           | Compound String [Term]
>           
> instance Show Term where
>     show (Atom a) = a
>     show (Number n) = show n
>     show (Variable x) = x
>     show term@(Compound f args) =
>		if f == "." then showList' term
>		else f ++ "(" ++ (intercalate ", " [ show arg | arg <- args ]) ++ ")"

> showList' :: Term -> String
> showList' list = "[" ++ showList'' list ++ "]"

TODO clean this up

> showList'' :: Term -> String
> showList'' (Compound "." [head, Variable v]) = (show head) ++ "|" ++ v
> showList'' (Compound "." [head, tail]) = (show head) ++ (if tail /= Atom "[]" then ", " else "") ++ showList'' tail
> showList'' (Atom "[]") = ""

> instance Eq Term where
>     (==) a b = (show a) == (show b)

> data Rule = Rule Term [Term]

> instance Show Rule where
>     show (Rule head body) = (show head) ++ (if body /= [] then " :- " else "") ++ intercalate ", " (map show body) ++ "."

> type Program = [Rule]

Parser algebra

> data Parser a = Parser (String -> [(a, String)])

> instance Functor Parser where
>     fmap = liftM

> instance Applicative Parser where
>     pure v = Parser (\input -> [(v, input)])
>     (<*>) = ap

> instance Monad Parser where
>     p >>= f = Parser (
>         \cs -> concat [parse' (f val) cs' | (val, cs') <- parse' p cs])
>     return = pure

> instance MonadPlus Parser where
>     mzero = Parser (\input -> [])
>     mplus p q = Parser (\input -> parse' p input ++ parse' q input) 

> instance Alternative Parser where
>     empty = mzero
>     (<|>) = mplus
>     many p = some p `mplus` return []
>     some p = do
>         a <- p
>         as <- many p
>         return (a:as)

> parse' :: Parser a -> String -> [(a, String)]
> parse' (Parser f) input = f input

> parse :: Parser a -> String -> a
> parse (Parser f) input = fst $ head $ f input

simple parsers: building blocks for other parsers

> char :: Char -> Parser Char
> char c = sat (c ==)

> string :: String -> Parser String
> string "" = return ""
> string (c:cs) = do
>     char c
>     string cs
>     return (c:cs)

> item :: Parser Char
> item = Parser (\input -> case input of
>     [] -> []
>     (c:cs) -> [(c, cs)])

> sat :: (Char -> Bool) -> Parser Char
> sat pred = do
>     c <- item
>     if pred c then return c else mzero

> sat2 :: (Char -> Bool) -> (Char -> Bool) -> Parser String
> sat2 initChar insideChar = do
>     c <- sat initChar
>     cs <- many (sat insideChar)
>     return (c:cs)

> space :: Parser String
> space = many (sat isSpace)

> triml :: Parser a -> Parser a
> triml p = do
>     space
>     r <- p
>     return r

> sepBy :: Parser a -> Parser b -> Parser [a]
> sepBy p sep = do
>     a <- p
>     as <- many (do {sep; p})
>     return (a:as)

> argList1 :: Parser a -> Parser [a]
> argList1 p = p `sepBy` comma

> argList :: Parser a -> Parser [a]
> argList p = argList1 p <|> return []

Prolog character classes and operator parsers

> dot = triml $ char '.'
> comma = triml $ char ','

> isIdentChar :: Char -> Bool
> isIdentChar c = isAlphaNum c || c == '_'

> smiley = triml $ string ":-"

Prolog language construct parsers

> variable :: Parser Term
> variable = fmap Variable $ sat2 isUpper isIdentChar

> atom :: Parser Term
> atom = fmap Atom $ sat2 (\c -> isLower c || c == '_') (\ c -> isIdentChar c || c == '_')

> number :: Parser Term
> number = fmap (Number . read) (some (sat isNumber))

> compound :: Parser Term
> compound = fmap (uncurry Compound) $ do
>     Atom f <- triml atom
>     char '(' -- don't triml here: space before `(' not allowed
>     args <- argList1 $ triml term
>     triml $ char ')'
>     return (f, args)

> emptyList :: Term
> emptyList = Atom "[]"

> list :: Parser Term
> list = do
>	char '['
>	do { triml $ char ']'; return emptyList} <|> list'

> list' :: Parser Term
> list' = fmap (uncurry Compound) $ do
>	head <- listHead
>	tail <- listTail
>	return (".", [head, tail])

> list'' :: Parser Term
> list'' = do
>	triml $ char ']'
>	return emptyList

> listHead :: Parser Term
> listHead = triml term <|> list''

> listTail :: Parser Term
> listTail = do { triml $ char '|'; triml list <|> listTailVar } <|> do { triml $ char ','; list' } <|> list''

> listTailVar :: Parser Term
> listTailVar = do
>	var <- triml variable
>	char ']'
>	return var

> term :: Parser Term
> term = list <|> compound <|> atom <|> variable <|> number

> rule :: Parser Rule
> rule = fmap (uncurry Rule) $ do
>     ruleHead <- term
>     body <- (do {smiley; argList term} <|> return [])
>     dot
>     return (ruleHead, body)

> program :: Parser Program
> program = do
>     space
>     rs <- many rule
>     return rs