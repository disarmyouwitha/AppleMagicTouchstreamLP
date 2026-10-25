// Read-only Ghidra export of an Apple trackpad driver.
// @category GlassToKey

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.DataIterator;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceIterator;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;

public class ExportAppleDriver extends GhidraScript {
    @Override
    protected void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length != 1) {
            throw new IllegalArgumentException("Expected one output directory argument");
        }
        File output = new File(args[0], currentProgram.getName() + ".analysis.txt");
        DecompInterface decompiler = new DecompInterface();
        try (PrintWriter writer = new PrintWriter(new OutputStreamWriter(
                new FileOutputStream(output), StandardCharsets.UTF_8))) {
            if (!decompiler.openProgram(currentProgram)) {
                throw new IllegalStateException("Ghidra decompiler could not open program");
            }
            writer.println("PROGRAM\t" + currentProgram.getName());
            writer.println("IMAGE_BASE\t" + currentProgram.getImageBase());
            writer.println("STRINGS");
            DataIterator data = currentProgram.getListing().getDefinedData(true);
            while (data.hasNext() && !monitor.isCancelled()) {
                Data item = data.next();
                Object value = item.getValue();
                if (value instanceof String) {
                    String escaped = ((String) value).replace("\r", "\\r")
                        .replace("\n", "\\n").replace("\t", "\\t");
                    writer.println("STRING\t" + item.getAddress() + "\t" + escaped);
                    ReferenceIterator refs = currentProgram.getReferenceManager()
                        .getReferencesTo(item.getAddress());
                    while (refs.hasNext()) {
                        Reference ref = refs.next();
                        writer.println("  XREF\t" + ref.getFromAddress() + "\t" + ref.getReferenceType());
                    }
                }
            }
            writer.println("FUNCTIONS");
            FunctionIterator functions = currentProgram.getFunctionManager().getFunctions(true);
            while (functions.hasNext() && !monitor.isCancelled()) {
                Function function = functions.next();
                writer.println("\nFUNCTION\t" + function.getEntryPoint() + "\t" + function.getName());
                ReferenceIterator refs = currentProgram.getReferenceManager()
                    .getReferencesTo(function.getEntryPoint());
                while (refs.hasNext()) {
                    Reference ref = refs.next();
                    writer.println("  XREF\t" + ref.getFromAddress() + "\t" + ref.getReferenceType());
                }
                DecompileResults result = decompiler.decompileFunction(function, 30, monitor);
                if (result.decompileCompleted() && result.getDecompiledFunction() != null) {
                    writer.println(result.getDecompiledFunction().getC());
                } else {
                    writer.println("DECOMPILE_ERROR\t" + result.getErrorMessage());
                }
                writer.flush();
            }
        } finally {
            decompiler.dispose();
        }
        println("Exported " + output.getAbsolutePath());
    }
}
