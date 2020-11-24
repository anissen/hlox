package cosy.phases;

import haxe.io.Bytes;
import haxe.io.BytesOutput;

enum ByteCodeOp {
    ConstantString(str: String);
    GetLocal(index: Int);
    SetLocal(index :Int);
    Pop(n: Int);
    PushTrue;
    PushFalse;
    PushNumber(n: Float);
    BinaryOp(type: TokenType);

    JumpIfFalse;
    JumpIfTrue;
    Jump;
    Print;
    Equal;
    Addition;
    Subtraction;
    Multiplication;
    Division;
    Less;
    LessEqual;
    Greater;
    GreaterEqual;
    Negate;
}

enum abstract ByteCodeOpValue(Int) to Int from Int {
    // New instructions *must* be added at the end to avoid breaking backwards compability
    final NoOp = 0;
    final ConstantString;
    final GetLocal;
    final SetLocal;
    final Pop;
    final PushTrue;
    final PushFalse;
    final PushNumber;
    final JumpIfFalse;
    final JumpIfTrue;
    final Jump;
    final Print;
    final Equal;
    final Addition;
    final Subtraction;
    final Multiplication;
    final Division;
    final Less;
    final LessEqual;
    final Greater;
    final GreaterEqual;
    final Negate;
}

class Output {
    public var strings: Array<String>;
    public var bytecode: Bytes;

    public function new() {
        strings = [];
    }
}

class CodeGenerator {
    var localsCounter :Int;
    var localIndexes :Map<String, Int>;
    var constantsCounter :Int;
    var codes: Array<ByteCodeOp>;
    var output: Output;

    var bytes: BytesOutput; // TODO: Bytecode may not be compatible between target languages due to differences in how bytes are represented in haxe.io.Bytes

	public function new() {

	}

	public inline function generate(stmts: Array<Stmt>): Output {
        localsCounter = 0;
        constantsCounter = 0;
        localIndexes = new Map();
        codes = [];
        output = new Output();
        bytes = new BytesOutput();
        genStmts(stmts);
        output.bytecode = bytes.getBytes();
        return output;
    }

	function genStmts(stmts: Array<Stmt>) {
        for (stmt in stmts) {
            genStmt(stmt);
        }
	}

    // function genExprs(exprs: Array<Expr>) {
    //     for (expr in exprs) {
    //         genExpr(expr);
    //     }
    // }

	function genStmt(stmt: Stmt) {
        if (stmt == null) return;
		switch stmt {
            case Print(keyword, expr):
                genExpr(expr);
                emit(Print);
            case Var(name, type, init, mut, foreign):
                genExpr(init);
                localIndexes[name.lexeme] = localsCounter++;
            case Block(statements):
                var previousLocalsCounter = localsCounter;
                genStmts(statements);
                var pops = localsCounter - previousLocalsCounter;
                if (pops > 0) emit(Pop(pops));
                localsCounter = previousLocalsCounter;
            case If(cond, then, el):
                genExpr(cond);
                var thenJump = emitJump(JumpIfFalse);
                emit(Pop(1));
                genStmt(then);
                
                var elseJump = emitJump(Jump);

                patchJump(thenJump);
                emit(Pop(1));

                if (el != null) genStmt(el);
                patchJump(elseJump);
            case ForCondition(cond, body):
                var loopStart = bytes.length;
                if (cond != null) {
                    genExpr(cond);
                    var exitJump = emitJump(JumpIfFalse);
                    emit(Pop(1));
                    genStmts(body);
                    
                    emitLoop(loopStart);

                    patchJump(exitJump);
                    emit(Pop(1));
                } else {
                    throw 'infinite loops are not yet implemented!';
                }
            case Expression(expr): genExpr(expr);
			case _: trace('Unhandled statement: $stmt'); [];
		}
    }
    
    // TODO: We also need line information for each bytecode
	function genExpr(expr: Expr) {
		switch expr {
            case Assign(name, op, value): genExpr(value); emit(SetLocal(localIndexes[name.lexeme]));
            case Binary(left, op, right): genExpr(left); genExpr(right); emit(BinaryOp(op.type));
            case Literal(v) if (Std.isOfType(v, Bool)): (v ? emit(PushTrue) : emit(PushFalse));
            case Literal(v) if (Std.isOfType(v, Float)): emit(PushNumber(v));
            case Literal(v) if (Std.isOfType(v, String)): emit(ConstantString(v));
            case Grouping(expr): genExpr(expr);
            case Variable(name): emit(GetLocal(localIndexes[name.lexeme]));
            case Logical(left, op, right):
                genExpr(left);
                switch op.type {
                    case And:
                        var endJump = emitJump(JumpIfFalse);
                        emit(Pop(1));
                        genExpr(right);
                        patchJump(endJump);
                    case Or:
                        var endJump = emitJump(JumpIfTrue);
                        emit(Pop(1));
                        genExpr(right);
                        patchJump(endJump);
                    case _: throw 'Unhandled Logical case!';
                }
            case Unary(op, right): 
                if (!op.type.match(Minus)) throw 'error';
                genExpr(right);
                emit(Negate);
			case _: trace('Unhandled expression: $expr'); [];
		}
    }

    function emit(op: ByteCodeOp) {
        switch op {
            case Print: 
                bytes.writeByte(ByteCodeOpValue.Print);
            case ConstantString(str):
                var stringIndex = output.strings.length;
                output.strings.push(str);
                bytes.writeByte(ByteCodeOpValue.ConstantString);
                bytes.writeInt32(stringIndex);
            case GetLocal(index): 
                bytes.writeByte(ByteCodeOpValue.GetLocal);
                bytes.writeByte(index);
            case SetLocal(index): 
                bytes.writeByte(ByteCodeOpValue.SetLocal);
                bytes.writeByte(index);
            case Pop(n): 
                bytes.writeByte(ByteCodeOpValue.Pop);
                bytes.writeByte(n);
            case PushTrue: 
                bytes.writeByte(ByteCodeOpValue.PushTrue);
            case PushFalse:
                bytes.writeByte(ByteCodeOpValue.PushFalse);
            case PushNumber(n):
                bytes.writeByte(ByteCodeOpValue.PushNumber);
                bytes.writeFloat(n);
            case BinaryOp(type): 
                bytes.writeByte(binaryOpCode(type));
            case JumpIfFalse:
                bytes.writeByte(ByteCodeOpValue.JumpIfFalse);
                bytes.writeInt32(666); // placeholder for jump argument
            case JumpIfTrue:
                bytes.writeByte(ByteCodeOpValue.JumpIfTrue);
                bytes.writeInt32(666); // placeholder for jump argument
            case Jump:
                bytes.writeByte(ByteCodeOpValue.Jump);
                bytes.writeInt32(666); // placeholder for jump argument
            case Equal: bytes.writeByte(ByteCodeOpValue.Equal);
            case Addition: bytes.writeByte(ByteCodeOpValue.Addition);
            case Subtraction: bytes.writeByte(ByteCodeOpValue.Subtraction);
            case Multiplication: bytes.writeByte(ByteCodeOpValue.Multiplication);
            case Division: bytes.writeByte(ByteCodeOpValue.Division);
            case Less: bytes.writeByte(ByteCodeOpValue.Less);
            case LessEqual: bytes.writeByte(ByteCodeOpValue.LessEqual);
            case Greater: bytes.writeByte(ByteCodeOpValue.Greater);
            case GreaterEqual: bytes.writeByte(ByteCodeOpValue.GreaterEqual);
            case Negate: bytes.writeByte(ByteCodeOpValue.Negate);
        }
    }

    function emitJump(op: ByteCodeOp): Int {
        emit(op);
        return bytes.length - 4; // -4 for the jump argument
    }

    function emitLoop(loopStart: Int) {
        bytes.writeByte(ByteCodeOpValue.Jump);
        var offset = bytes.length - loopStart + 4;
        bytes.writeInt32(-offset);
    }

    function patchJump(offset: Int) {
        var jump = bytes.length - offset - 4;
        overwriteInstruction(offset, jump);
    }

    // TODO: This is probably expensive, but there seems to be no other way (except having the bytes buffer be an Array<Int>)
    function overwriteInstruction(pos: Int, value: Int) {
        final currentBytes = bytes.getBytes();
        currentBytes.setInt32(pos, value);
        bytes = new BytesOutput();
        bytes.write(currentBytes);
    }

    function binaryOpCode(type: TokenType): ByteCodeOpValue {
        return switch type {
            case EqualEqual: Equal;
            case Plus: Addition;
            case Minus: Subtraction;
            case Star: Multiplication;
            case Slash: Division;
            case Less: Less;
            case LessEqual: LessEqual;
            case Greater: Greater;
            case GreaterEqual: GreaterEqual;
            case _: trace('unhandled type: $type'); throw 'error';
        }
    }
}
