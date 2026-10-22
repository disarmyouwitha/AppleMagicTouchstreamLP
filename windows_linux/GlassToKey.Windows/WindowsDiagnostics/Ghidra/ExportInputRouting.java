// Static export only: selected functions and bounded direct callees. Never calls the inspected APIs.
// @category GlassToKey
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import java.io.File;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayDeque;
import java.util.HashSet;
import java.util.Set;

public class ExportInputRouting extends GhidraScript {
    private static class Item {
        Function function; int depth;
        Item(Function f, int d) { function = f; depth = d; }
    }
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) throw new IllegalArgumentException("output directory and function names required");
        File output = new File(args[0], currentProgram.getName() + ".routing.txt");
        ArrayDeque<Item> queue = new ArrayDeque<>();
        Set<String> visited = new HashSet<>();
        DecompInterface decompiler = new DecompInterface();
        try (PrintWriter writer = new PrintWriter(output, StandardCharsets.UTF_8.name())) {
            writer.println("PROGRAM " + currentProgram.getName());
            writer.println("IMAGE_BASE " + currentProgram.getImageBase());
            for (int i = 1; i < args.length; i++) for (String name : args[i].split(",")) {
                if (name.startsWith("0x")) {
                    Function f = getFunctionAt(toAddr(name));
                    if (f == null) writer.println("MISSING " + name);
                    else queue.add(new Item(f,0));
                    continue;
                }
                if (getGlobalFunctions(name).isEmpty()) writer.println("MISSING " + name);
                for (Function f : getGlobalFunctions(name)) queue.add(new Item(f,0));
            }
            if (!decompiler.openProgram(currentProgram)) throw new IllegalStateException("Decompiler failed");
            while (!queue.isEmpty() && visited.size() < 100 && !monitor.isCancelled()) {
                Item item = queue.remove();
                Function f = item.function;
                if (!visited.add(f.getEntryPoint().toString())) continue;
                writer.println("\nFUNCTION " + f.getEntryPoint() + " " + f.getName() + " depth=" + item.depth);
                DecompileResults result = decompiler.decompileFunction(f,30,monitor);
                if (result.decompileCompleted() && result.getDecompiledFunction()!=null)
                    writer.println(result.getDecompiledFunction().getC());
                else writer.println("DECOMPILE_ERROR " + result.getErrorMessage());
                writer.println("ASSEMBLY");
                InstructionIterator instructions = currentProgram.getListing().getInstructions(f.getBody(),true);
                while (instructions.hasNext()) {
                    Instruction instruction = instructions.next();
                    writer.println(instruction.getAddress() + " " + instruction);
                }
                if (item.depth < 2) for (Function callee : f.getCalledFunctions(monitor)) {
                    String name = callee.getName();
                    if (!callee.isExternal() && !name.startsWith("Etw") && !name.startsWith("WPP") &&
                        !name.startsWith("__") && !name.startsWith("_guard")) queue.add(new Item(callee,item.depth+1));
                }
                writer.flush();
            }
            writer.println("EXPORTED_FUNCTION_COUNT " + visited.size());
            writer.println("REMAINING_QUEUED " + queue.size());
        } finally { decompiler.dispose(); }
        println("Exported " + output.getAbsolutePath());
    }
}
