%code requires {
  #include <memory>
  #include <string>

  #include <sstream>

}

%{

#include <iostream>
#include <memory>
#include <string>

#include <sstream>
// 声明 lexer 函数和错误处理函数
int yylex();
void yyerror(std::unique_ptr<BaseAST> &ast, const char *s);

using namespace std;

string format_float(float value)
{
  stringstream ss;
  ss<<value;
  string s=ss.str();
  if(s.find('.')!=string::npos){
    s.erase(s.find_last_not_of('0')+1,string::nops);
    if(s.back()=='.'){
      s.pop_back();
    }
  }
  return s;
}
%}

// 定义 parser 函数和错误处理函数的附加参数
// 我们需要返回一个字符串作为 AST, 所以我们把附加参数定义成字符串的智能指针
// 解析完成后, 我们要手动修改这个参数, 把它设置成解析得到的字符串
%parse-param { std::unique_ptr<BaseAST> &ast }

// yylval 的定义, 我们把它定义成了一个联合体 (union)
// 因为 token 的值有的是字符串指针, 有的是整数
// 之前我们在 lexer 中用到的 str_val 和 int_val 就是在这里被定义的
// 至于为什么要用字符串指针而不直接用 string 或者 unique_ptr<string>?
// 请自行 STFW 在 union 里写一个带析构函数的类会出现什么情况
%union {
  std::string *str_val;
  int int_val;

  float float_val;
}

// lexer 返回的所有 token 种类的声明
// 注意 IDENT 和 INT_CONST 会返回 token 的值, 分别对应 str_val 和 int_val
%token INT FLOAT RETURN
%token <str_val> IDENT
%token <int_val> INT_CONST
%token <float_val> FLOAT_CONST

// 非终结符的类型定义
%type <ast_val> Number Stmt Block FuncType FuncDef

%%

// 开始符, CompUnit ::= FuncDef, 大括号后声明了解析完成后 parser 要做的事情
// 之前我们定义了 FuncDef 会返回一个 str_val, 也就是字符串指针
// 而 parser 一旦解析完 CompUnit, 就说明所有的 token 都被解析了, 即解析结束了
// 此时我们应该把 FuncDef 返回的结果收集起来, 作为 AST 传给调用 parser 的函数
// $1 指代规则里第一个符号的返回值, 也就是 FuncDef 的返回值
CompUnit
  : FuncDef {
      auto comp_unit = std::make_unique<CompUnitAST>();
      comp_unit->func_def_vec.push_back(std::unique_ptr<FuncDefAST>(static_cast<FuncDefAST*>($1)));
      ast = std::move(comp_unit);  // ast 类型是 unique_ptr<BaseAST>
  }
  ;

// FuncDef ::= FuncType IDENT '(' ')' Block;
// 我们这里可以直接写 '(' 和 ')', 因为之前在 lexer 里已经处理了单个字符的情况
// 解析完成后, 把这些符号的结果收集起来, 然后拼成一个新的字符串, 作为结果返回
// $$ 表示非终结符的返回值, 我们可以通过给这个符号赋值的方法来返回结果
// 你可能会问, FuncType, IDENT 之类的结果已经是字符串指针了
// 为什么还要用 unique_ptr 接住它们, 然后再解引用, 把它们拼成另一个字符串指针呢
// 因为所有的字符串指针都是我们 new 出来的, new 出来的内存一定要 delete
// 否则会发生内存泄漏, 而 unique_ptr 这种智能指针可以自动帮我们 delete
// 虽然此处你看不出用 unique_ptr 和手动 delete 的区别, 但当我们定义了 AST 之后
// 这种写法会省下很多内存管理的负担
FuncDef
  : FuncType IDENT '(' ')' Block {
      auto funcDef = new FuncDefAST();
      funcDef->func_type.reset(static_cast<FuncTypeAST*>($1));  // 显式转换
      funcDef->ident = *$2;                                      // 解引用指针
      funcDef->block_vec.emplace_back(static_cast<BlockAST*>($5));  // 显式转换

      $$ = funcDef;
  }
  ;

// 同上, 不再解释
FuncType
  : INT {
      auto funcType = new FuncTypeAST();
      funcType->func_type = FuncTypeAST::FUNC_TYPE_INT;
      $$ = funcType;
  }
  | FLOAT{
    $$ = new string("float");
  }
  ;

Block
  : '{' Stmt '}' {
      auto block = new BlockAST();
      auto block_item = new BlockItemAST(BlockItemAST::BLOCK_ITEM_STMT);
      block_item->stmt.reset(static_cast<StmtAST*>($2));
      block->block_item_vec.emplace_back(block_item);
      $$ = block;
  }
  ;


Stmt
  : RETURN Number ';' {
      auto stmt = new StmtAST(StmtAST::STMT_RETURN);
      stmt->exp.reset(dynamic_cast<ExpAST*>($2));
      $$ = stmt;
  }
  ;

Number
  : INT_CONST {
      $$ = new NumberAST($1);
  }
  | FLOAT_CONST{
    $$ =new string(format_float($1));
  }
  ;

%%

// 定义错误处理函数, 其中第二个参数是错误信息
// parser 如果发生错误 (例如输入的程序出现了语法错误), 就会调用这个函数
void yyerror(unique_ptr<BaseAST> &ast, const char *s) {
  cerr << "error: " << s << endl;
}
