/*
 * Hunt - a framework for web and console application based on Collie using Dlang development
 *
 * Copyright (C) 2015-2016  Shanghai Putao Technology Co., Ltd 
 *
 * Developer: putao's Dlang team
 *
 * Licensed under the BSD License.
 *
 * template parsing is based on dymk/temple source from https://github.com/dymk/temple
 */
module hunt.web.view.func_string_gen;

public import hunt.web.view, hunt.web.view.util, hunt.web.view.delims, std.conv,
    std.string, std.array, std.exception, std.uni, std.algorithm;

/**
 * Stack and generator for unique temporary variable names
 */
private struct TempBufferNameStack
{
private:
    const string base;
    uint counter = 0;
    string[] stack;

public:
    this(string base)
    {
        this.base = base;
    }

    /**
	 * getNew
	 * Gets a new unique buffer variable name
	 */
    string pushNew()
    {
        auto name = base ~ counter.to!string;
        counter++;
        stack ~= name;
        return name;
    }

    /**
	 * Pops the topmost unique variable name off the stack
	 */
    string pop()
    {
        auto ret = stack[$ - 1];
        stack.length--;
        return ret;
    }

    /**
	 * Checks if there are any names to pop off
	 */
    bool empty()
    {
        return !stack.length;
    }
}

/**
 * Represents a unit of code that makes up the template function
 */
private struct FuncPart
{
    enum Type
    {
        StrLit, // String literal appended to the buffer
        Expr, // Runtime computed expression appended to the buffer
        Stmt, // Any arbitrary statement/declaration making up the function
        Line, // #line directive
    }

    Type type;
    string value;
    uint indent;
}

/**
 * __temple_gen_temple_func_string
 * Generates the function string to be mixed into a template which renders
 * a temple file.
 */
package string __temple_gen_temple_func_string(string temple_str,
    in string temple_name, in string filter_ident = "")
{
    // Output function string being composed
    FuncPart[] func_parts;

    // Indendation level for a line being pushed
    uint indent_level = 0;

    // Current line number in the temple_str being scanned
    size_t line_number = 0;

    // Generates temporary variable names and keeps them on a stack
    auto temp_var_names = TempBufferNameStack("__temple_capture_var_");

    // Content removed from the head of temple_str is put on the tail of this
    string prev_temple_str = "";

    /* ----- func_parts appending functions ----- */
    void push_expr(string expr)
    {
        func_parts ~= FuncPart(FuncPart.Type.Expr, expr, indent_level);
    }

    void push_stmt(string stmt)
    {
        func_parts ~= FuncPart(FuncPart.Type.Stmt, stmt ~ '\n', indent_level);
    }

    void push_string_literal(string str)
    {
        func_parts ~= FuncPart(FuncPart.Type.StrLit, str, indent_level);
    }

    void push_linenum()
    {
        func_parts ~= FuncPart(FuncPart.Type.Line,
            `#line %d "%s"`.format(line_number + 1, temple_name) ~ "\n", indent_level);
    }

    void push_linenumanno(string anno)
    {
        func_parts ~= FuncPart(FuncPart.Type.Line,
                `#line %d "%s-------%s"`.format(line_number + 1, temple_name,anno) ~ "\n", indent_level);
    }
    /* ----------------------------------------- */

    void indent()
    {
        indent_level++;
    }

    void outdent()
    {
        indent_level--;
    }

    // Tracks if the block that the parser has just
    // finished processing should be printed (e.g., is
    // it the block who's contents are assigned to the last tmp_buffer_var)
    bool[] printStartBlockTracker;
    void sawBlockStart(bool will_be_printed)
    {
        printStartBlockTracker ~= will_be_printed;
    }

    bool sawBlockEnd()
    {
        auto will_be_printed = printStartBlockTracker[$ - 1];
        printStartBlockTracker.length--;
        return will_be_printed;
    }

    // Generate the function signature, taking into account if it has a
    // FilterParam to use
    push_stmt(build_function_head(filter_ident));

    indent();
    if (filter_ident.length)
    {
        push_stmt(`with(%s)`.format(filter_ident));
    }
    push_stmt(`with(__temple_context) {`);
    indent();

    // Keeps infinite loops from outright crashing the compiler
    // The limit should be set to some arbitrary large number
    uint safeswitch = 0;
	
    while (temple_str.length)
    {
        // This imposes the limiatation of a max of 10_000 delimers parsed for
        // a template function. Probably will never ever hit this in a single
        // template file without running out of compiler memory
        if (safeswitch++ > 10_000)
        {
            assert(false, "nesting level too deep; throwing saftey switch: \n" ~ temple_str);
        }

        DelimPos!(OpenDelim)* oDelimPos = temple_str.nextDelim(OpenDelims);


		pragma(msg,"context parsing..............................................");
        if (oDelimPos is null)
        {
            //No more delims; append the rest as a string
            push_linenum();
            push_string_literal(temple_str);
            prev_temple_str.munchHeadOf(temple_str, temple_str.length);
        }
        else
        {
            immutable OpenDelim oDelim = oDelimPos.delim;
            immutable CloseDelim cDelim = OpenToClose[oDelim];

			pragma(msg,"delim check........................");
            if (oDelimPos.pos == 0)
            {
				//-------------give it
                if (oDelim.isShort())
                {
                    if (!prev_temple_str.validBeforeShort())
                    {
                        // Chars before % weren't all whitespace, assume it's part of a
                        // string literal.
                        push_linenum();
                        push_string_literal(temple_str[0 .. oDelim.toString().length]);
                        prev_temple_str.munchHeadOf(temple_str, oDelim.toString().length);
                        continue;
                    }
                }
				//------------give it end

                // If we made it this far, we've got valid open/close delims
                DelimPos!(CloseDelim)* cDelimPos = temple_str.nextDelim([cDelim]);
                if (cDelimPos is null)
                {
                    if (oDelim.isShort())
                    {
                        // don't require a short close delim at the end of the template
                        temple_str ~= cDelim.toString();
                        cDelimPos = enforce(temple_str.nextDelim([cDelim]));
                    }
                    else
                    {
                        assert(false, "Missing close delimer: " ~ cDelim.toString());
                    }
                }

                // Made it this far, we've got the position of the close delimer.
                push_linenum();

                // Get a slice to the content between the delimers
                immutable string inbetween_delims = temple_str[oDelim.toString()
                    .length .. cDelimPos.pos];

                // track block starts
                immutable bool is_block_start = inbetween_delims.isBlockStart();
                immutable bool is_block_end = inbetween_delims.isBlockEnd();

                // Invariant
                assert(!(is_block_start && is_block_end), "Internal bug: " ~ inbetween_delims);

                if (is_block_start)
                {
                    sawBlockStart(oDelim.isStr());
                }

                if (oDelim.isStr())
                {
                    // Check if this is a block; in that case, put the block's
                    // contents into a temporary variable, then render that
                    // variable after the block close delim

                    // The line would look like:
                    // <%= capture(() { %>
                    //  <% }); %>
                    // so look for something like "){" or ") {" at the end

                    if (is_block_start)
                    {
                        string tmp_name = temp_var_names.pushNew();
                        push_stmt(`auto %s = %s`.format(tmp_name, inbetween_delims));
                        indent();
                    }
                    else
                    {
                        push_expr(inbetween_delims);

                        if (cDelim == CloseDelim.CloseShort)
                        {
                            push_stmt(`__temple_buff_filtered_put("\n");`);
                        }
                    }
                }
				/*
				else if(oDelim.isIncludeStr())
				{
					push_linenumanno("compile_temple_file!" ~ inbetween_delims);
					//TODO parsing includ template
                    //auto inTemple = import(inbetween_delims);
				}
				*/
                else
                {
                    // It's just raw code, push it into the function body
                    push_stmt(inbetween_delims);

                    // Check if the code looks like the ending to a block;
                    // e.g. for block:
                    // <%= capture(() { %>
                    // <% }, "foo"); %>`
                    // look for it starting with }<something>);
                    // If it does, output the last tmp buffer var on the stack
                    if (is_block_end && !temp_var_names.empty)
                    {

                        // the block at this level should be printed
                        if (sawBlockEnd())
                        {
                            outdent();
                            push_stmt(`__temple_context.put(%s);`.format(temp_var_names.pop()));
                        }
                    }
                }

                // remove up to the closing delimer
                prev_temple_str.munchHeadOf(temple_str, cDelimPos.pos + cDelim.toString().length);
            }
            else
            {
                // Move ahead to the next open delimer, rendering
                // everything between here and there as a string literal
                push_linenum();
                immutable delim_pos = oDelimPos.pos;
                push_string_literal(temple_str[0 .. delim_pos]);
                prev_temple_str.munchHeadOf(temple_str, delim_pos);
            }
        }

        // count the number of newlines in the previous part of the template;
        // that's the current line number
        line_number = prev_temple_str.count('\n');
    }

    outdent();
    push_stmt("}");
    outdent();
    push_stmt("}");

    return buildFromParts(func_parts);
}

private:

string build_function_head(string filter_ident)
{
    string ret = "";

    string function_type_params = filter_ident.length ? "(%s)".format(filter_ident) : "";

    ret ~= (
        `static void TempleFunc%s(TempleContext __temple_context) {`.format(function_type_params));

    // This isn't just an overload of __temple_buff_filtered_put because D doesn't allow
    // overloading of nested functions
    ret ~= `
	// Ensure that __temple_context is never null
	assert(__temple_context);

	void __temple_put_expr(T)(T expr) {

		// TempleInputStream should never be passed through
		// a filter; it should be directly appended to the stream
		static if(is(typeof(expr) == TempleInputStream))
		{
			expr.into(__temple_context.sink);
		}

		// But other content should be filtered
		else
		{
			__temple_buff_filtered_put(expr);
		}
	}

	deprecated auto renderWith(string __temple_file)(TempleContext tc = null)
	{
		return render_with!__temple_file(tc);
	}
	TempleInputStream render(string __temple_file)() {
		return render_with!__temple_file(__temple_context);
	}
	`;

    // Is the template using a filter?
    if (filter_ident.length)
    {
        ret ~= `
	/// Run 'thing' through the Filter's templeFilter static
	void __temple_buff_filtered_put(T)(T thing)
	{
		static if(__traits(compiles, __fp__.templeFilter(__temple_context.sink, thing)))
		{
			pragma(msg, "Deprecated: templeFilter on filters is deprecated; please use temple_filter");
			__fp__.templeFilter(__temple_context.sink, thing);
		}
		else static if(__traits(compiles, __fp__.templeFilter(thing)))
		{
			pragma(msg, "Deprecated: templeFilter on filters is deprecated; please use temple_filter");
			__temple_context.put(__fp__.templeFilter(thing));
		}
		else static if(__traits(compiles, __fp__.temple_filter(__temple_context.sink, thing))) {
			__fp__.temple_filter(__temple_context.sink, thing);
		}
		else static if(__traits(compiles, __fp__.temple_filter(thing)))
		{
			__temple_context.put(__fp__.temple_filter(thing));
		}
		else {
			// Fall back to templeFilter returning a string
			static assert(false, "Filter does not have a case that accepts a " ~ T.stringof);
		}
	}

	/// with filter, render subtemplate with an explicit context (which defaults to null)
	TempleInputStream render_with(string __temple_file)(TempleContext tc = null)
	{
		return TempleInputStream(delegate(ref TempleOutputStream s) {
			auto nested = compile_temple_file!(__temple_file, __fp__)();
			nested.render(s, tc);
		});
	}
	`
            .replace("__fp__", filter_ident);
    }
    else
    {
        // No filter means just directly append the thing to the
        // buffer, converting it to a string if needed
        ret ~= `
	void __temple_buff_filtered_put(T)(T thing)
	{
                static import std.conv;
		__temple_context.put(std.conv.to!string(thing));
	}

	/// without filter, render subtemplate with an explicit context (which defaults to null)
	TempleInputStream render_with(string __temple_file)(TempleContext tc = null)
	{
		return TempleInputStream(delegate(ref TempleOutputStream s) {
			auto nested = compile_temple_file!(__temple_file)();
			nested.render(s, tc);
		});
	}
	`;
    }

    return ret;
}

string buildFromParts(in FuncPart[] parts)
{
    string func_str = "";

    foreach (index, immutable part; parts)
    {
        string indent()
        {
            string ret = "";
            for (int i = 0; i < part.indent; i++)
                ret ~= '\t';
            return ret;
        }

        func_str ~= indent();

        final switch (part.type) with (FuncPart.Type)
        {
        case Stmt:
        case Line:
            func_str ~= part.value;
            break;

        case Expr:
            func_str ~= "__temple_put_expr(" ~ part.value.strip ~ ");\n";
            break;

        case StrLit:
            if (index > 1 && (index + 2) < parts.length)
            {
                // look ahead/behind 2 because the generator inserts
                // #line annotations after each statement/expr/literal
                immutable prev_type = parts[index - 2].type;
                immutable next_type = parts[index + 2].type;

                // if the previous and next parts are statements, and this part is all
                // whitespace, skip inserting it into the template
                if (prev_type == FuncPart.Type.Stmt
                        && next_type == FuncPart.Type.Stmt
                        && part.value.all!((chr) => chr.isWhite()))
                {
                    break;
                }
            }

            func_str ~= `__temple_context.put("` ~ part.value.replace("\n",
                "\\n").escapeQuotes() ~ "\");\n";
            break;
        }
    }

    return func_str;
}
