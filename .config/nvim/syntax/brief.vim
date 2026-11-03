" Basic Brief highlighting; no Treesitter parser required.
if exists('b:current_syntax')
  finish
endif

syntax case match
syntax sync minlines=50

syntax match briefIdentifier /\<[A-Za-z_][A-Za-z0-9_]*\>/
" Functions have no declaration keyword; highlight names before a call/parameter list.
syntax match briefFunction /\<[A-Za-z_][A-Za-z0-9_]*\>\ze\s*(/
" Nominal types conventionally start with a capital letter.
syntax match briefType /\<[A-Z][A-Za-z0-9_]*\>/
syntax keyword briefType bool chr str shrt ushrt int uint lng ulng flt dub Self Sym Fn
syntax keyword briefKeyword let var const type impl trait pub ovr
syntax keyword briefInclude import mod
syntax keyword briefConditional if else
syntax keyword briefRepeat for in while
syntax keyword briefStatement ret break continue
syntax keyword briefBoolean true false
syntax keyword briefOperator and or
syntax match briefOperator /[-+*\/%=<>!&|^~?]/
syntax match briefDelimiter /[(){}\[\],.:]/
syntax match briefOperator /\.\./
" A tag's colon touches its name, unlike the usual field/type annotation.
syntax match briefSymbol /\%([A-Za-z0-9_]\)\@<!:[A-Za-z_][A-Za-z0-9_]*/

" Source literals are decimal (no exponent notation); don't consume range dots.
syntax match briefNumber /\<\d\+\>/
syntax match briefFloat /\<\d\+\.\d\+\>/
syntax match briefEscape /\\[nt\\"'0]/ contained
syntax region briefString start=/"/ skip=/\\./ end=/"/ oneline contains=briefEscape
syntax region briefCharacter start=/'/ skip=/\\./ end=/'/ oneline contains=briefEscape

syntax keyword briefTodo TODO FIXME XXX NOTE contained
syntax match briefComment +//.*$+ contains=briefTodo,@Spell
syntax region briefComment start=+/\*+ end=+\*/+ contains=briefTodo,@Spell

highlight default link briefIdentifier Identifier
highlight default link briefFunction Function
highlight default link briefType Type
highlight default link briefKeyword Keyword
highlight default link briefInclude Include
highlight default link briefConditional Conditional
highlight default link briefRepeat Repeat
highlight default link briefStatement Statement
highlight default link briefBoolean Boolean
highlight default link briefOperator Operator
highlight default link briefDelimiter Delimiter
highlight default link briefSymbol Constant
highlight default link briefNumber Number
highlight default link briefFloat Float
highlight default link briefEscape SpecialChar
highlight default link briefString String
highlight default link briefCharacter Character
highlight default link briefComment Comment
highlight default link briefTodo Todo

let b:current_syntax = 'brief'
