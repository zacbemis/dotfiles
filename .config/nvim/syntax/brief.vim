" Basic Brief highlighting; no Treesitter parser required.
if exists('b:current_syntax')
  finish
endif

syntax case match
" Design notes can be long block comments; keep highlighting correct on a direct jump.
syntax sync fromstart

syntax match briefIdentifier /\<[A-Za-z_][A-Za-z0-9_]*\>/
" Calls and fn declarations share the same name highlighting.
syntax match briefFunction /\<[A-Za-z_][A-Za-z0-9_]*\>\ze\s*(/
" Nominal types conventionally start with a capital letter.
syntax match briefType /\<[A-Z][A-Za-z0-9_]*\>/
syntax keyword briefType bln chr str shrt ushrt int uint lng ulng flt dbl
syntax keyword briefKeyword let var fn as
syntax keyword briefKeyword type nextgroup=briefTypeName skipwhite skipempty
syntax match briefTypeName /\<[A-Za-z_][A-Za-z0-9_]*\>/ contained
syntax keyword briefInclude mod nextgroup=briefTypeName skipwhite skipempty
syntax keyword briefConditional if then else
syntax keyword briefRepeat for in while
syntax keyword briefStatement ret yield break continue
syntax keyword briefBoolean true false
syntax keyword briefOperator and or
syntax match briefOperator /[-+*\/%=<>!&|^~?]/
syntax match briefDelimiter /[(){}\[\],.:]/
syntax match briefOperator /\.\.\|:=\|->\||>/
" Consume the entire tag (including error prefixes and keyword-like names).
syntax match briefSymbol /#!\?[A-Za-z_][A-Za-z0-9_]*/
" Checked construction and qualified abstract module types, e.g. t := [], B.t.
syntax match briefType /\<[A-Za-z_][A-Za-z0-9_]*\>\ze\s*:=/
syntax match briefType /\%(\.\)\@<=t\>/

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
highlight default link briefTypeName Type
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
