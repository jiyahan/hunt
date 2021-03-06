/*
 * Hunt - a framework for web and console application based on Collie using Dlang development
 *
 * Copyright (C) 2015-2016  Shanghai Putao Technology Co., Ltd 
 *
 * Developer: putao's Dlang team
 *
 * Licensed under the BSD License.
 *
 */
module hunt.web.router.configsignalmodule;

import std.file;
import std.string;
import std.regex;
import std.stdio;
import std.array;
import std.uni;
import std.conv;
import std.experimental.logger;

import hunt.web.router.configbase;
/**
 * example: *     /show      index.show
 * toParse: [GET,POST...]  /show   application.controllers.index.IndexController.show
 */
final class ConfigSignalModule : ConfigLine
{
    /*
     * @Param filePath - path of file
     * @Param prefix - prefix of module's full path, use "application.controllers" for default
     */
    this(string filePath, string prefix = "application.controllers.")
    {
        super(filePath, prefix);
    }

public:
    override RouterContext[] doParse()
    {
        RouterContext[] routerContext;
        
        File file = File(filePath, "r");

        while(!file.eof())
        {
            string line = file.readln();
            if (line != string.init && (line.indexOf('#') < 0))
            {
                string[] tmpSplites = spliteBySpace(line);
                if(tmpSplites.length == 0) continue;
                RouterContext tmpRoute;
                if (tmpSplites[0] == "*")
                    tmpRoute.method = fullMethod;
                else
                    tmpRoute.method = toUpper(tmpSplites[0]);
                tmpRoute.path = tmpSplites[1];
		tmpRoute.hander = parseToFullController(tmpSplites[2]);
		tmpRoute.routerType = RouterType.DEFAULT;
                
		if (tmpSplites.length == 4)
                    parseMiddleware(tmpSplites[3], tmpRoute.middleWareBefore,
                        tmpRoute.middleWareAfter);
                routerContext ~= tmpRoute;
            }
        }
        return routerContext;
    }
private:
    string parseToFullController(string inBuff)
    {
        string[] spritArr = split(inBuff, '.');
        assert(spritArr.length > 1, "whitout .");
        string output;
        spritArr[spritArr.length - 2] = spritArr[spritArr.length - 2] ~"."~ to!string(spritArr[spritArr.length - 2].asCapitalized) ~ controllerPrefix;
        output ~= prefix;
        output ~= spritArr.join(".");
	trace("output: ", output);
	return output;
    }
}
